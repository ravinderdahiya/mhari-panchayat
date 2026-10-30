<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\GisController;
use App\Http\Controllers\Api\LocationController;
use App\Models\AppVersion;
use App\Models\AssetType;
use App\Models\Block;
use App\Models\CitizenProfile;
use App\Models\Complaint;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\User;
use App\Models\Village;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class JourneyGis extends GisController
{
    public string $status = 'matched';

    public function pointStatus(float $latitude, float $longitude): array
    {
        return ['status' => $this->status, 'code' => '1', 'name' => 'Satrod'];
    }
}

class JourneyLocations extends LocationController
{
    public function lookup(float $latitude, float $longitude): ?array
    {
        return ['district' => 'Hisar', 'tehsil' => 'Hisar', 'block' => 'Hisar I', 'panchayat' => 'Satrod', 'village' => 'Satrod Kalan'];
    }
}

/**
 * One citizen's whole journey through the real HTTP stack and database: sign in,
 * share a location, file a complaint (geofence), get it tracked on the public
 * page, have staff act on it, and see all of it in the admin panel's data.
 */
class IntegrationJourneyTest extends TestCase
{
    use RefreshDatabase;

    private array $ids = [];

    private JourneyGis $gis;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        Storage::fake('public');
        $this->seed(PermissionSeeder::class);

        $this->gis = new JourneyGis;
        $this->app->instance(GisController::class, $this->gis);
        $this->app->instance(LocationController::class, new JourneyLocations);

        $state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $district = District::create(['name' => 'Hisar', 'code' => 'HSR', 'state_id' => $state->id]);
        $tehsil = Tehsil::create(['name' => 'Hisar', 'code' => 'HIS', 'district_id' => $district->id]);
        $block = Block::create(['name' => 'Hisar I', 'code' => 'HIS1', 'district_id' => $district->id]);
        $panchayat = Panchayat::create(['name' => 'Satrod', 'code' => 'SAT', 'block_id' => $block->id]);
        $village = Village::create(['name' => 'Satrod Kalan', 'code' => 'SATK', 'panchayat_id' => $panchayat->id, 'tehsil_id' => $tehsil->id]);
        $department = Department::create(['name' => 'Rural Development', 'code' => 'RD']);
        $assetType = AssetType::create(['name' => 'Hand Pump', 'icon_key' => 'water_drop']);
        $assetType->departments()->attach($department);

        $this->ids = [
            'district_id' => $district->id, 'tehsil_id' => $tehsil->id, 'village_id' => $village->id,
            'category_id' => ComplaintCategory::create(['name' => 'Road', 'code' => 'ROAD', 'sort_order' => 1])->id,
            'priority_id' => ComplaintPriority::create(['name' => 'Medium', 'level' => 2, 'sla_hours' => 72])->id,
            'department_id' => $department->id,
            'asset_type_id' => $assetType->id,
        ];
    }

    private function citizen(): User
    {
        $user = User::factory()->create(['role' => 'citizen', 'mobile' => '9876543210']);
        CitizenProfile::create([
            'user_id' => $user->id, 'full_name' => 'Ramesh', 'mobile' => '9876543210',
            'registration_source' => 'mobile_app', 'registered_at' => now(),
        ]);

        return $user;
    }

    private function fileComplaint(User $citizen)
    {
        return $this->actingAs($citizen, 'sanctum')->post('/api/complaints', $this->ids + [
            'description' => 'The village road has a large unsafe pothole.',
            'lat' => 29.1492,
            'long' => 75.7217,
            'photo' => UploadedFile::fake()->create('pothole.jpg', 100, 'image/jpeg'),
        ]);
    }

    public function test_a_citizens_complaint_is_visible_end_to_end(): void
    {
        $citizen = $this->citizen();
        $admin = User::factory()->create(['role' => 'admin']);

        // 1. The app shares the citizen's location after sign-in.
        $this->actingAs($citizen, 'sanctum')
            ->putJson('/api/auth/citizen/location', ['latitude' => 29.1492, 'longitude' => 75.7217])
            ->assertOk()->assertJsonPath('saved', true);

        // 2. Capture GPS inside a village boundary is accepted, and so is the complaint.
        $this->actingAs($citizen, 'sanctum')
            ->getJson('/api/auth/citizen/geofence?latitude=29.1492&longitude=75.7217')
            ->assertOk()->assertJsonPath('allowed', true);
        $response = $this->fileComplaint($citizen)->assertCreated()->assertJsonPath('complaint.status', 'Pending');
        $code = $response->json('complaint.code');
        $id = $response->json('complaint.id');

        // 3. Anyone with the ID and the filer's mobile can track it on the public page.
        $this->postJson('/api/public/track-complaint', ['complaint_id' => $code, 'mobile' => '9876543210'])
            ->assertOk()->assertJsonPath('data.stage', 0)->assertJsonPath('data.status', 'Pending');
        $this->postJson('/api/public/track-complaint', ['complaint_id' => $code, 'mobile' => '9000000000'])->assertNotFound();

        // 4. The admin panel's lists show the complaint and the citizen's location.
        $this->actingAs($admin, 'sanctum')->getJson('/api/complaints')
            ->assertOk()->assertJsonFragment(['code' => $code]);
        $row = $this->actingAs($admin, 'sanctum')->getJson('/api/citizens')->assertOk()->json('citizens.0');
        $this->assertSame(1, $row['complaintsCount']);
        $this->assertSame('Hisar', $row['location']['district']);
        $this->assertSame('device', $row['location']['source']);

        // 5. A panchayat official acknowledges it: the public tracker moves on and the citizen is notified.
        $staff = User::factory()->create(['role' => 'sarpanch']);
        $this->actingAs($staff, 'sanctum')->patchJson("/api/complaints/{$id}/acknowledge")
            ->assertOk()->assertJsonPath('complaint.status', 'Acknowledged');
        Cache::flush();
        $this->postJson('/api/public/track-complaint', ['complaint_id' => $code, 'mobile' => '9876543210'])
            ->assertOk()->assertJsonPath('data.status', 'Acknowledged')->assertJsonPath('data.stage', 2);
        $this->assertDatabaseHas('user_notifications', ['user_id' => $citizen->id, 'complaint_id' => $id]);

        // 6. The public home page counts it.
        $this->getJson('/api/public/home')->assertJsonPath('data.stats.complaints_total', 1);
    }

    public function test_a_complaint_from_outside_any_village_is_refused_and_not_saved(): void
    {
        $citizen = $this->citizen();
        $this->gis->status = 'none';

        $this->actingAs($citizen, 'sanctum')
            ->getJson('/api/auth/citizen/geofence?latitude=28.6&longitude=77.2')
            ->assertOk()->assertJsonPath('allowed', false);

        $this->fileComplaint($citizen)->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonFragment(['message' => \App\Services\CitizenGeofence::MESSAGE]);

        $this->assertSame(0, Complaint::count());
    }

    public function test_a_complaint_still_goes_through_when_the_boundary_service_is_down(): void
    {
        $this->gis->status = 'unavailable';

        $this->fileComplaint($this->citizen())->assertCreated();
        $this->assertSame(1, Complaint::count());
    }

    public function test_a_citizen_must_send_gps_and_staff_are_not_geofenced(): void
    {
        $citizen = $this->citizen();
        $payload = $this->ids + ['description' => 'The village road has a large unsafe pothole.', 'photo' => UploadedFile::fake()->create('p.jpg', 100, 'image/jpeg')];

        $this->actingAs($citizen, 'sanctum')->post('/api/complaints', $payload)
            ->assertStatus(422)->assertJsonFragment(['message' => 'GPS location is required to file a complaint']);

        // A staff account filing from outside a boundary is not blocked by the citizen rule.
        $this->gis->status = 'none';
        $staff = User::factory()->create(['role' => 'admin']);
        $this->actingAs($staff, 'sanctum')->post('/api/complaints', $payload + ['lat' => 28.6, 'long' => 77.2])
            ->assertCreated();
    }

    public function test_an_outdated_app_build_is_stopped_at_sign_in_before_any_of_this(): void
    {
        AppVersion::updateOrCreate(['platform' => 'android'], ['latest_version_code' => 3, 'min_version_code' => 3, 'store_url' => 'https://example.com']);

        $this->withHeader('X-App-Version-Code', '2')
            ->postJson('/api/auth/login', ['username' => 'x', 'password' => 'y'])
            ->assertStatus(426)->assertJsonPath('status', 'force_update');
    }
}
