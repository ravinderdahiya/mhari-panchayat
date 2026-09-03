<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdminUserPasswordApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_users_list_includes_revealed_login_password_but_auth_me_does_not(): void
    {
        $admin = User::factory()->create([
            'role' => 'super_admin',
            'password' => 'Admin@1234',
        ]);
        $officer = User::factory()->create([
            'role' => 'ddpo',
            'password' => 'Officer@123',
        ]);

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonMissingPath('user.login_password');

        $this->actingAs($admin, 'sanctum')
            ->getJson('/api/users?page=1&per_page=10')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonFragment(['id' => $officer->id, 'login_password' => 'Officer@123']);

        $this->assertTrue(Hash::check('Officer@123', $officer->fresh()->password));
        $this->assertArrayNotHasKey('login_password_enc', $this->actingAs($admin, 'sanctum')->getJson('/api/users?page=1')->json('users.0'));
    }

    public function test_admin_can_set_a_user_password_and_then_see_it(): void
    {
        $admin = User::factory()->create(['role' => 'super_admin', 'password' => 'Admin@1234']);
        $officer = User::factory()->create(['role' => 'ddpo']);

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/users/'.$officer->id, ['password' => 'NewPass@99'])
            ->assertOk()
            ->assertJsonPath('user.login_password', 'NewPass@99');

        $this->assertTrue(Hash::check('NewPass@99', $officer->fresh()->password));
    }
}
