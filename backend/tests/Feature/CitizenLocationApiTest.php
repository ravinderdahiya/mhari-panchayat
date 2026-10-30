<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\GisController;
use App\Http\Controllers\Api\LocationController;
use App\Models\CitizenProfile;
use App\Models\User;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StubLocations extends LocationController
{
    public function lookup(float $latitude, float $longitude): ?array
    {
        return [
            'district' => 'Hisar', 'tehsil' => 'Hisar', 'block' => 'Hisar I',
            'panchayat' => 'Satrod', 'village' => 'Satrod Kalan',
        ];
    }
}

class StubGis extends GisController
{
    public string $status = 'none';

    public function pointStatus(float $latitude, float $longitude): array
    {
        return ['status' => $this->status, 'code' => '1', 'name' => 'Satrod'];
    }
}

class CitizenLocationApiTest extends TestCase
{
    use RefreshDatabase;

    private function citizen(string $mobile = '9876500009'): User
    {
        $user = User::factory()->create(['role' => 'citizen', 'mobile' => $mobile]);
        CitizenProfile::create([
            'user_id' => $user->id, 'full_name' => 'Citizen', 'mobile' => $mobile,
            'registration_source' => 'mobile_app', 'registered_at' => now(),
        ]);

        return $user;
    }

    public function test_location_is_saved_resolved_by_the_server_with_a_full_address(): void
    {
        $this->app->instance(LocationController::class, new StubLocations);
        $citizen = $this->citizen();

        $this->actingAs($citizen, 'sanctum')
            ->putJson('/api/auth/citizen/location', ['latitude' => 29.1393, 'longitude' => 75.7047])
            ->assertOk()->assertJsonPath('saved', true);

        $profile = CitizenProfile::where('user_id', $citizen->id)->first();
        $this->assertSame('Hisar', $profile->district);
        $this->assertSame('Satrod Kalan', $profile->village);
        $this->assertSame('Satrod Kalan, Satrod, Hisar, Hisar I, Haryana', $profile->address);
        $this->assertEqualsWithDelta(29.1393, $profile->latitude, 0.00001);
    }

    public function test_location_validates_coordinates_and_ignores_staff_without_a_citizen_profile(): void
    {
        $this->app->instance(LocationController::class, new StubLocations);

        $this->actingAs($this->citizen(), 'sanctum')
            ->putJson('/api/auth/citizen/location', ['latitude' => 120, 'longitude' => 75])
            ->assertStatus(422)->assertJsonValidationErrors('latitude');

        $this->actingAs(User::factory()->create(['role' => 'sarpanch']), 'sanctum')
            ->putJson('/api/auth/citizen/location', ['latitude' => 29.1, 'longitude' => 75.7])
            ->assertOk()->assertJsonPath('saved', false);
    }

    public function test_admin_citizens_list_shows_the_saved_location(): void
    {
        $this->seed(PermissionSeeder::class);
        $this->app->instance(LocationController::class, new StubLocations);
        $citizen = $this->citizen();
        $this->actingAs($citizen, 'sanctum')->putJson('/api/auth/citizen/location', ['latitude' => 29.1, 'longitude' => 75.7]);

        $row = $this->actingAs(User::factory()->create(['role' => 'admin']), 'sanctum')
            ->getJson('/api/citizens')->assertOk()->json('citizens.0');

        $this->assertSame('device', $row['location']['source']);
        $this->assertSame('Hisar', $row['location']['district']);
        $this->assertEqualsWithDelta(75.7, $row['location']['long'], 0.00001);
    }

    public function test_citizen_without_any_location_has_a_null_location(): void
    {
        $this->seed(PermissionSeeder::class);
        $this->citizen();

        $this->actingAs(User::factory()->create(['role' => 'admin']), 'sanctum')
            ->getJson('/api/citizens')->assertOk()->assertJsonPath('citizens.0.location', null);
    }

    public function test_geofence_endpoint_refuses_points_outside_a_village_and_allows_inside(): void
    {
        $gis = new StubGis;
        $this->app->instance(GisController::class, $gis);
        $citizen = $this->citizen();

        $gis->status = 'none';
        $this->actingAs($citizen, 'sanctum')
            ->getJson('/api/auth/citizen/geofence?latitude=28.6&longitude=77.2')
            ->assertOk()->assertJsonPath('allowed', false);

        $gis->status = 'matched';
        $this->actingAs($citizen, 'sanctum')
            ->getJson('/api/auth/citizen/geofence?latitude=29.1&longitude=75.7')
            ->assertOk()->assertJsonPath('allowed', true)->assertJsonPath('message', null);
    }

    public function test_geofence_endpoint_requires_a_login_and_valid_coordinates(): void
    {
        $this->getJson('/api/auth/citizen/geofence?latitude=29&longitude=75')->assertUnauthorized();

        $this->actingAs($this->citizen(), 'sanctum')
            ->getJson('/api/auth/citizen/geofence')->assertStatus(422);
    }
}
