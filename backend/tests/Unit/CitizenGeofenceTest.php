<?php

namespace Tests\Unit;

use App\Http\Controllers\Api\GisController;
use App\Models\CitizenProfile;
use App\Models\User;
use App\Services\CitizenGeofence;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class FakeGis extends GisController
{
    public array $result = ['status' => 'none'];

    public bool $throws = false;

    public function pointStatus(float $latitude, float $longitude): array
    {
        if ($this->throws) {
            throw new \RuntimeException('boom');
        }

        return $this->result;
    }
}

class CitizenGeofenceTest extends TestCase
{
    use RefreshDatabase;

    private function citizen(): User
    {
        $user = User::factory()->create(['role' => 'citizen']);
        CitizenProfile::create([
            'user_id' => $user->id, 'full_name' => 'Test', 'mobile' => '9876500009',
            'registration_source' => 'mobile_app', 'registered_at' => now(),
        ]);

        return $user;
    }

    private function fence(array $result = ['status' => 'none'], bool $throws = false): CitizenGeofence
    {
        $gis = new FakeGis;
        $gis->result = $result;
        $gis->throws = $throws;

        return new CitizenGeofence($gis);
    }

    public function test_point_inside_a_village_boundary_is_allowed(): void
    {
        $check = $this->fence(['status' => 'matched', 'code' => '123', 'name' => 'Satrod'])->check($this->citizen(), 29.1, 75.7);

        $this->assertTrue($check['allowed']);
        $this->assertSame('Satrod', $check['panchayat']);
        $this->assertNull($check['message']);
    }

    public function test_point_outside_every_boundary_is_refused_with_a_bilingual_message(): void
    {
        $check = $this->fence(['status' => 'none'])->check($this->citizen(), 28.6, 77.2);

        $this->assertFalse($check['allowed']);
        $this->assertStringContainsString('गाँव', $check['message']);
        $this->assertStringContainsString('village', $check['message']);
    }

    public function test_unreachable_boundary_service_does_not_block_the_citizen(): void
    {
        $this->assertTrue($this->fence(['status' => 'unavailable'])->check($this->citizen(), 29.1, 75.7)['allowed']);
    }

    public function test_an_exception_in_the_check_fails_open(): void
    {
        $this->assertTrue($this->fence(throws: true)->check($this->citizen(), 29.1, 75.7)['allowed']);
    }

    public function test_staff_accounts_are_never_restricted(): void
    {
        $staff = User::factory()->create(['role' => 'sarpanch']);

        $this->assertTrue($this->fence(['status' => 'none'])->check($staff, 28.6, 77.2)['allowed']);
    }
}
