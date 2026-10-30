<?php

namespace Tests\Feature;

use App\Models\AssetSurvey;
use App\Models\AssetType;
use App\Models\Block;
use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class PublicHomeApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
    }

    private function complaint(string $mobile = '9876543210', array $overrides = []): Complaint
    {
        $department = Department::firstOrCreate(['code' => 'PWD'], ['name' => 'Public Works Department']);
        $assetType = AssetType::firstOrCreate(['name' => 'Road'], ['icon_key' => 'road']);
        $assetType->departments()->syncWithoutDetaching([$department->id]);
        $priority = ComplaintPriority::firstOrCreate(['name' => 'Medium'], ['level' => 2, 'sla_hours' => 72]);
        $citizen = User::factory()->create(['role' => 'citizen', 'mobile' => $mobile]);

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

    private function survey(AssetType $type, string $status): void
    {
        $department = Department::firstOrCreate(['code' => 'GEN'], ['name' => 'General']);
        $surveyor = User::factory()->create(['role' => 'cplo']);
        AssetSurvey::forceCreate([
            'surveyor_id' => $surveyor->id, 'department_id' => $department->id, 'asset_type_id' => $type->id,
            'asset_name' => 'Asset', 'district' => 'Hisar', 'panchayat' => 'Satrod', 'village' => 'Satrod',
            'latitude' => 29.1, 'longitude' => 75.7, 'condition' => 'good', 'survey_date' => now(),
            'photo_paths' => '[]', 'review_status' => $status,
        ]);
    }

    private function panchayat(): Panchayat
    {
        $state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $district = District::create(['name' => 'Hisar', 'code' => 'HSR', 'state_id' => $state->id]);
        $block = Block::create(['name' => 'Hisar I', 'code' => 'HIS1', 'district_id' => $district->id]);

        return Panchayat::create(['name' => 'Satrod', 'code' => 'SAT', 'block_id' => $block->id]);
    }

    public function test_home_returns_stats_contact_and_default_play_store_link(): void
    {
        $this->complaint();

        $response = $this->getJson('/api/public/home')
            ->assertOk()
            ->assertJsonPath('data.stats.complaints_total', 1)
            ->assertJsonPath('data.stats.complaints_resolved', 0)
            ->assertJsonPath('data.announcement', null)
            ->assertJsonStructure(['data' => ['stats', 'asset_types' => ['total', 'featured'], 'contact', 'app' => ['android_url', 'ios_url'], 'generated_at']]);

        $this->assertStringContainsString('in.hsac.mharipanchayat', $response->json('data.app.android_url'));
    }

    public function test_asset_type_legend_counts_only_approved_assets(): void
    {
        $type = AssetType::create(['name' => 'Chaupal', 'icon_key' => 'x', 'is_active' => true]);
        $this->survey($type, 'approved');
        $this->survey($type, 'pending');

        $featured = collect($this->getJson('/api/public/home')->json('data.asset_types.featured'))->firstWhere('name', 'Chaupal');

        $this->assertSame(1, $featured['count']);
    }

    public function test_tracker_returns_status_for_the_right_id_and_mobile(): void
    {
        $complaint = $this->complaint('9876543210');

        $this->postJson('/api/public/track-complaint', ['complaint_id' => strtolower($complaint->code), 'mobile' => '9876543210'])
            ->assertOk()
            ->assertJsonPath('data.complaint_id', $complaint->code)
            ->assertJsonPath('data.stage', 0)
            ->assertJsonCount(6, 'data.steps');
    }

    public function test_tracker_gives_the_same_404_for_unknown_id_and_wrong_mobile(): void
    {
        $complaint = $this->complaint('9876543210');

        $wrongMobile = $this->postJson('/api/public/track-complaint', ['complaint_id' => $complaint->code, 'mobile' => '9123456789']);
        $unknownId = $this->postJson('/api/public/track-complaint', ['complaint_id' => 'COMP-XXX-00_0000-999', 'mobile' => '9876543210']);

        $wrongMobile->assertNotFound();
        $unknownId->assertNotFound();
        $this->assertSame($wrongMobile->json('message'), $unknownId->json('message'));
    }

    public function test_tracker_rejects_a_malformed_mobile_number(): void
    {
        $this->postJson('/api/public/track-complaint', ['complaint_id' => 'COMP-1', 'mobile' => '12345'])
            ->assertStatus(422)->assertJsonValidationErrors('mobile');
    }

    public function test_tracker_does_not_leak_the_owner(): void
    {
        $complaint = $this->complaint('9876543210');

        $body = $this->postJson('/api/public/track-complaint', ['complaint_id' => $complaint->code, 'mobile' => '9876543210'])->json('data');

        $this->assertArrayNotHasKey('user', $body);
        $this->assertArrayNotHasKey('mobile', $body);
    }

    public function test_search_needs_two_characters_and_matches_panchayat_names(): void
    {
        $this->panchayat();

        $this->getJson('/api/public/search?q=s')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/public/search?q=satr')->assertOk()
            ->assertJsonPath('data.0.name', 'Satrod')
            ->assertJsonPath('data.0.district', 'Hisar');
    }

    public function test_public_assets_lists_only_approved_points(): void
    {
        $type = AssetType::create(['name' => 'School', 'icon_key' => 'x']);
        $this->survey($type, 'approved');
        $this->survey($type, 'rejected');

        $this->getJson('/api/public/assets')->assertOk()->assertJsonPath('data.total', 1);
    }

    public function test_funds_demo_is_stable_flagged_and_balanced(): void
    {
        $panchayat = $this->panchayat();

        $first = $this->getJson("/api/public/funds?panchayat_id={$panchayat->id}&fy=2026-27")->assertOk();
        $second = $this->getJson("/api/public/funds?panchayat_id={$panchayat->id}&fy=2026-27");

        $first->assertJsonPath('data.demo', true)->assertJsonCount(6, 'data.sources');
        $this->assertSame($first->json('data.received_lakh'), $second->json('data.received_lakh'));
        $this->assertEqualsWithDelta(
            $first->json('data.received_lakh') - $first->json('data.spent_lakh'),
            $first->json('data.balance_lakh'),
            0.01,
        );
    }

    public function test_funds_validates_input_and_unknown_panchayat(): void
    {
        $this->getJson('/api/public/funds')->assertStatus(422);
        $this->getJson('/api/public/funds?panchayat_id=999999&fy=2026-27')->assertNotFound();
        $this->getJson('/api/public/funds?panchayat_id=1&fy=bad')->assertStatus(422);
    }
}
