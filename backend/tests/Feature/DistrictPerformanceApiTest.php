<?php

namespace Tests\Feature;

use App\Models\AssetType;
use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\District;
use App\Models\State;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

/**
 * "Top districts by SLA compliance" for the public home page.
 *
 * A complaint is judged against its priority's SLA hours:
 *   on time = resolved/closed within sla_hours of being filed
 *   breach  = resolved/closed later than that, or still open with its SLA already past
 * compliance % = on time / (on time + breach). Rejected complaints, complaints whose
 * priority has no SLA, and open complaints still inside their SLA do not count.
 * A district needs at least 3 judged complaints to be ranked; the top 5 are shown.
 */
class DistrictPerformanceApiTest extends TestCase
{
    use RefreshDatabase;

    private State $state;

    private User $citizen;

    private Department $department;

    private AssetType $assetType;

    private ComplaintPriority $priority;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $this->state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $this->citizen = User::factory()->create(['role' => 'citizen']);
        $this->department = Department::create(['name' => 'Rural Development', 'code' => 'RD']);
        $this->assetType = AssetType::create(['name' => 'Road', 'icon_key' => 'road']);
        $this->priority = ComplaintPriority::create(['name' => 'Medium', 'level' => 2, 'sla_hours' => 72]);
    }

    private function district(string $name): District
    {
        // A unique short code per district keeps the generated complaint numbers (COMP-<code>-...) unique.
        $code = strtoupper(substr(md5($name), 0, 4));

        return District::forceCreate(['name' => $name, 'code' => $code, 'short_code' => $code, 'state_id' => $this->state->id]);
    }

    /** @param  array<string, mixed>  $overrides */
    private function complaint(District $district, string $status, ?int $resolvedAfterHours = null, array $overrides = []): Complaint
    {
        $filed = now()->subDays(30);
        $priority = $overrides['priority'] ?? $this->priority;
        unset($overrides['priority']);

        return Complaint::forceCreate([
            'user_id' => $this->citizen->id,
            'priority_id' => $priority->id,
            'department_id' => $this->department->id,
            'asset_type_id' => $this->assetType->id,
            'district_id' => $district->id,
            'description' => 'Road has a large pothole outside the school.',
            'status' => $status,
            'created_at' => $filed,
            'updated_at' => $filed,
            'resolved_at' => $resolvedAfterHours === null ? null : $filed->copy()->addHours($resolvedAfterHours),
            'sla_due_at' => $resolvedAfterHours === null ? $filed->copy()->addHours($priority->sla_hours ?? 0) : null,
            ...$overrides,
        ]);
    }

    /** Three on-time resolutions - the smallest set that gets a district ranked. */
    private function perfectDistrict(string $name, int $extraOnTime = 0): District
    {
        $district = $this->district($name);
        foreach (range(1, 3 + $extraOnTime) as $_) {
            $this->complaint($district, 'Resolved', 10);
        }

        return $district;
    }

    private function ranking(): array
    {
        return $this->getJson('/api/public/district-performance')->assertOk()->json('data.districts');
    }

    public function test_is_empty_when_there_is_no_data(): void
    {
        $this->getJson('/api/public/district-performance')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.districts', [])
            ->assertJsonPath('data.min_sample', 3);
    }

    public function test_is_public_and_needs_no_login(): void
    {
        $this->getJson('/api/public/district-performance')->assertOk();
    }

    public function test_compliance_is_the_share_of_on_time_resolutions(): void
    {
        $district = $this->district('Hisar');
        $this->complaint($district, 'Resolved', 10);
        $this->complaint($district, 'Resolved', 60);
        $this->complaint($district, 'Closed', 72);   // exactly on the limit still counts as on time
        $this->complaint($district, 'Resolved', 100); // late

        $row = $this->ranking()[0];

        $this->assertSame('Hisar', $row['district']);
        $this->assertEqualsWithDelta(75.0, $row['compliance'], 0.01);
        $this->assertSame(4, $row['judged']);
        $this->assertSame(1, $row['rank']);
    }

    public function test_an_open_complaint_past_its_sla_counts_as_a_breach(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $this->complaint($district, 'Pending'); // filed 30 days ago, SLA was 72 hours

        $this->assertEqualsWithDelta(75.0, $this->ranking()[0]['compliance'], 0.01);
    }

    public function test_an_open_complaint_still_inside_its_sla_is_not_counted(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $this->complaint($district, 'Pending', null, ['created_at' => now()->subHours(5), 'sla_due_at' => now()->addHours(67)]);

        $row = $this->ranking()[0];

        $this->assertEqualsWithDelta(100.0, $row['compliance'], 0.01);
        $this->assertSame(3, $row['judged']);
    }

    public function test_rejected_complaints_are_ignored(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $this->complaint($district, 'Rejected', null);
        $this->complaint($district, 'Rejected', 500);

        $row = $this->ranking()[0];

        $this->assertEqualsWithDelta(100.0, $row['compliance'], 0.01);
        $this->assertSame(3, $row['judged']);
    }

    public function test_complaints_whose_priority_has_no_sla_are_ignored(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $noSla = ComplaintPriority::create(['name' => 'Informational', 'level' => 1, 'sla_hours' => null]);
        $this->complaint($district, 'Resolved', 9999, ['priority' => $noSla]);

        $this->assertSame(3, $this->ranking()[0]['judged']);
    }

    public function test_a_district_with_too_few_judged_complaints_is_not_ranked(): void
    {
        $small = $this->district('Panipat');
        $this->complaint($small, 'Resolved', 10);
        $this->complaint($small, 'Resolved', 10);
        $this->perfectDistrict('Hisar');

        $names = array_column($this->ranking(), 'district');

        $this->assertSame(['Hisar'], $names);
    }

    public function test_districts_are_ranked_by_compliance_then_by_volume_then_by_name(): void
    {
        $this->perfectDistrict('Sirsa');                 // 100%, 3 judged
        $this->perfectDistrict('Bhiwani', 2);            // 100%, 5 judged -> ahead of Sirsa
        $this->perfectDistrict('Ambala');                // 100%, 3 judged -> ties with Sirsa, wins on name
        $mixed = $this->perfectDistrict('Rohtak');       // 75%
        $this->complaint($mixed, 'Resolved', 500);

        $ranked = $this->ranking();

        $this->assertSame(['Bhiwani', 'Ambala', 'Sirsa', 'Rohtak'], array_column($ranked, 'district'));
        $this->assertSame([1, 2, 3, 4], array_column($ranked, 'rank'));
    }

    public function test_only_the_top_five_districts_are_returned(): void
    {
        foreach (['A1', 'B2', 'C3', 'D4', 'E5', 'F6'] as $name) {
            $this->perfectDistrict($name);
        }

        $this->assertCount(5, $this->ranking());
    }

    public function test_complaints_without_a_district_are_ignored(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $this->complaint($district, 'Resolved', 999, ['district_id' => null]);

        $this->assertSame(3, $this->ranking()[0]['judged']);
    }

    public function test_exposes_only_aggregates_never_complaint_or_citizen_details(): void
    {
        $this->perfectDistrict('Hisar');

        $row = $this->ranking()[0];

        $this->assertEqualsCanonicalizing(['rank', 'district', 'compliance', 'judged'], array_keys($row));
    }

    public function test_result_is_cached_for_a_few_minutes(): void
    {
        $district = $this->perfectDistrict('Hisar');
        $this->assertCount(1, $this->ranking());

        $this->perfectDistrict('Rohtak');

        $this->assertCount(1, $this->ranking(), 'a second call within the cache window should not recompute');
        Cache::forget('public.district_performance');
        $this->assertCount(2, $this->ranking());
    }
}
