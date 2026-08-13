<?php

namespace Tests\Feature;

use App\Console\Commands\AutoCloseResolvedComplaints;
use App\Console\Commands\EscalateOverdueComplaints;
use App\Models\AssetType;
use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\User;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ComplaintWorkflowApiTest extends TestCase
{
    use RefreshDatabase;

    private function makeComplaint(array $overrides = []): Complaint
    {
        $department = Department::create(['name' => 'Public Works Department', 'code' => 'PWD']);
        $assetType = AssetType::create(['name' => 'Road', 'icon_key' => 'road']);
        $assetType->departments()->attach($department);
        $priority = ComplaintPriority::create(['name' => 'Medium', 'level' => 2, 'sla_hours' => 72]);
        $citizen = User::factory()->create(['role' => 'citizen']);

        return Complaint::create([
            'user_id' => $citizen->id,
            'priority_id' => $priority->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'description' => 'Road has a large pothole outside the school.',
            'status' => 'Pending',
            ...$overrides,
        ])->refresh();
    }

    public function test_reject_notifies_the_citizen_and_blocks_further_rejection(): void
    {
        $this->seed(PermissionSeeder::class);
        $complaint = $this->makeComplaint();
        $staff = User::factory()->create(['role' => 'sarpanch']);

        $response = $this->actingAs($staff, 'sanctum')
            ->patchJson("/api/complaints/{$complaint->id}/reject", ['reason' => 'Duplicate of an existing repair order']);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('complaint.status', 'Rejected');

        $this->assertDatabaseHas('complaint_timeline_events', [
            'complaint_id' => $complaint->id,
            'status' => 'Rejected',
            'title' => 'Complaint Rejected',
        ]);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $complaint->user_id,
            'type' => 'COMPLAINT_REJECTED',
            'complaint_id' => $complaint->id,
        ]);

        $again = $this->actingAs($staff, 'sanctum')
            ->patchJson("/api/complaints/{$complaint->id}/reject", ['reason' => 'Retry'])
            ->assertStatus(400);
        $again->assertJsonPath('success', false);
    }

    public function test_store_sets_sla_due_at_from_the_chosen_priority(): void
    {
        $this->seed(PermissionSeeder::class);
        $department = Department::create(['name' => 'Public Works Department', 'code' => 'PWD']);
        $assetType = AssetType::create(['name' => 'Road', 'icon_key' => 'road']);
        $assetType->departments()->attach($department);
        $priority = ComplaintPriority::create(['name' => 'High', 'level' => 3, 'sla_hours' => 24]);
        $citizen = User::factory()->create(['role' => 'citizen']);

        $response = $this->actingAs($citizen, 'sanctum')->postJson('/api/complaints', [
            'priority_id' => $priority->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
            'location_district' => 'Hisar',
            'location_village' => 'Satrod Kalan',
            'description' => 'Streetlight has been broken for a week.',
            'photo' => \Illuminate\Http\UploadedFile::fake()->create('light.jpg', 50, 'image/jpeg'),
        ]);

        $response->assertCreated();
        $complaint = Complaint::findOrFail($response->json('complaint.id'));
        $this->assertNotNull($complaint->sla_due_at);
        $this->assertTrue($complaint->sla_due_at->between(now()->addHours(23), now()->addHours(25)));
    }

    public function test_escalate_overdue_bumps_priority_and_notifies_department_head(): void
    {
        $complaint = $this->makeComplaint(['status' => 'Acknowledged']);
        ComplaintPriority::create(['name' => 'High', 'level' => 3, 'sla_hours' => 24]);
        $departmentHead = User::factory()->create(['role' => 'department_head', 'department_id' => $complaint->department_id]);
        $complaint->update(['sla_due_at' => now()->subHour()]);

        $this->artisan(EscalateOverdueComplaints::class)->assertExitCode(0);

        $complaint->refresh();
        $this->assertSame('High', $complaint->priority->name);
        $this->assertSame(1, $complaint->escalation_level);
        $this->assertNotNull($complaint->escalated_at);
        $this->assertTrue($complaint->sla_due_at->isFuture());

        $this->assertDatabaseHas('complaint_timeline_events', [
            'complaint_id' => $complaint->id,
            'title' => 'SLA Breached — Escalated',
        ]);
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $departmentHead->id,
            'type' => 'COMPLAINT_ESCALATED',
            'complaint_id' => $complaint->id,
        ]);
    }

    public function test_escalate_overdue_ignores_complaints_still_within_sla(): void
    {
        $complaint = $this->makeComplaint(['status' => 'Acknowledged', 'sla_due_at' => now()->addDay()]);

        $this->artisan(EscalateOverdueComplaints::class)->assertExitCode(0);

        $complaint->refresh();
        $this->assertSame(0, $complaint->escalation_level);
        $this->assertSame('Medium', $complaint->priority->name);
    }

    public function test_auto_close_resolved_complaints_past_the_response_window(): void
    {
        $complaint = $this->makeComplaint([
            'status' => 'Resolved',
            'resolved_at' => now()->subDays(8),
        ]);
        $recent = $this->makeComplaint([
            'status' => 'Resolved',
            'resolved_at' => now()->subDays(2),
        ]);

        $this->artisan(AutoCloseResolvedComplaints::class)->assertExitCode(0);

        $this->assertSame('Closed', $complaint->refresh()->status);
        $this->assertSame('Resolved', $recent->refresh()->status);
        $this->assertDatabaseHas('complaint_timeline_events', [
            'complaint_id' => $complaint->id,
            'title' => 'Auto-closed',
        ]);
    }

    public function test_reopen_notifies_the_previous_assignee(): void
    {
        $this->seed(PermissionSeeder::class);
        $assignee = User::factory()->create(['role' => 'engineer']);
        $complaint = $this->makeComplaint(['status' => 'Closed', 'assigned_to_id' => $assignee->id]);

        $response = $this->actingAs($complaint->user, 'sanctum')
            ->patchJson("/api/complaints/{$complaint->id}/reopen", ['reason' => 'Pothole is back after the rain']);

        $response->assertOk()->assertJsonPath('complaint.status', 'Reopened');
        $this->assertDatabaseHas('user_notifications', [
            'user_id' => $assignee->id,
            'type' => 'COMPLAINT_ASSIGNED',
            'complaint_id' => $complaint->id,
        ]);
    }
}
