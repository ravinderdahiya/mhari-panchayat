<?php

namespace Tests\Feature;

use App\Models\LoginLog;
use App\Models\User;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class LoginLogApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $this->seed(PermissionSeeder::class);
    }

    private function staff(array $attrs = []): User
    {
        return User::factory()->create(array_merge([
            'username' => 'ddpo.karnal',
            'password' => 'secret-pass',
            'role' => 'ddpo',
            'is_active' => true,
            'registration_status' => 'active',
        ], $attrs));
    }

    public function test_successful_staff_login_is_recorded_with_ip_and_device(): void
    {
        $user = $this->staff();

        $this->withHeader('User-Agent', 'Mozilla/5.0 TestBrowser')
            ->postJson('/api/auth/login', ['username' => 'ddpo.karnal', 'password' => 'secret-pass'])
            ->assertOk();

        $log = LoginLog::sole();
        $this->assertSame($user->id, $log->user_id);
        $this->assertSame('success', $log->status);
        $this->assertSame('password', $log->method);
        $this->assertSame('ddpo.karnal', $log->identifier);
        $this->assertSame('ddpo', $log->role);
        $this->assertSame('127.0.0.1', $log->ip_address);
        $this->assertSame('Mozilla/5.0 TestBrowser', $log->user_agent);
    }

    public function test_wrong_password_is_recorded_as_failed_without_storing_the_password(): void
    {
        $user = $this->staff();

        $this->postJson('/api/auth/login', ['username' => 'ddpo.karnal', 'password' => 'wrong-guess'])
            ->assertStatus(401);

        $log = LoginLog::sole();
        $this->assertSame('failed', $log->status);
        $this->assertSame($user->id, $log->user_id);
        $this->assertSame('Invalid credentials', $log->reason);
        $this->assertStringNotContainsString('wrong-guess', json_encode($log->toArray()));
    }

    public function test_unknown_username_is_recorded_as_failed_with_no_user(): void
    {
        $this->postJson('/api/auth/login', ['username' => 'nobody', 'password' => 'x'])->assertStatus(401);

        $log = LoginLog::sole();
        $this->assertNull($log->user_id);
        $this->assertSame('nobody', $log->identifier);
        $this->assertSame('failed', $log->status);
    }

    public function test_disabled_account_login_is_recorded_as_failed_with_reason(): void
    {
        $this->staff(['is_active' => false]);

        $this->postJson('/api/auth/login', ['username' => 'ddpo.karnal', 'password' => 'secret-pass'])
            ->assertForbidden();

        $this->assertSame('Account is disabled', LoginLog::sole()->reason);
    }

    public function test_citizen_otp_login_and_bad_otp_are_recorded(): void
    {
        // .env may carry a static bypass code; keep this test independent of it.
        config(['services.otp_bypass.code' => null, 'services.otp_demo.code' => null]);

        $this->postJson('/api/auth/verify-otp', ['mobile' => '9999999999', 'otp' => '5678'])->assertStatus(400);
        $this->postJson('/api/auth/verify-otp', ['mobile' => '9999999999', 'otp' => '0000'])->assertOk();

        $logs = LoginLog::orderBy('id')->get();
        $this->assertCount(2, $logs);
        $this->assertSame(['failed', 'success'], $logs->pluck('status')->all());
        $this->assertSame('otp', $logs[1]->method);
        $this->assertSame('citizen', $logs[1]->role);
        $this->assertNotNull($logs[1]->user_id);
    }

    public function test_only_audit_permission_holders_can_list_login_logs(): void
    {
        $this->getJson('/api/login-logs')->assertUnauthorized();

        $this->actingAs(User::factory()->create(['role' => 'sarpanch']), 'sanctum')
            ->getJson('/api/login-logs')->assertForbidden();

        // audit.view belongs to super admins by default (PermissionSeeder).
        $this->actingAs(User::factory()->create(['role' => 'admin']), 'sanctum')
            ->getJson('/api/login-logs')->assertForbidden();

        $this->actingAs(User::factory()->create(['role' => 'super_admin']), 'sanctum')
            ->getJson('/api/login-logs')->assertOk();
    }

    public function test_login_logs_are_paginated(): void
    {
        foreach (range(1, 23) as $i) {
            LoginLog::create([
                'identifier' => "user{$i}", 'method' => 'password', 'status' => 'failed',
                'created_at' => now()->subMinutes(30 - $i),
            ]);
        }

        $this->actingAs(User::factory()->create(['role' => 'super_admin']), 'sanctum');

        $this->getJson('/api/login-logs?per_page=10')
            ->assertJsonCount(10, 'logs')
            ->assertJsonPath('meta.total', 23)
            ->assertJsonPath('meta.lastPage', 3)
            ->assertJsonPath('meta.perPage', 10)
            ->assertJsonPath('logs.0.identifier', 'user23');

        $this->getJson('/api/login-logs?per_page=10&page=3')
            ->assertJsonCount(3, 'logs')
            ->assertJsonPath('meta.page', 3)
            ->assertJsonPath('logs.2.identifier', 'user1')
            // summary covers every page, not just the visible one
            ->assertJsonPath('summary.failed', 23);

        $this->getJson('/api/login-logs?per_page=5')->assertUnprocessable();
    }

    public function test_admin_sees_newest_first_and_can_filter_by_status_and_search(): void
    {
        $user = $this->staff(['name' => 'Karnal DDPO']);
        $this->postJson('/api/auth/login', ['username' => 'ddpo.karnal', 'password' => 'bad'])->assertStatus(401);
        $this->postJson('/api/auth/login', ['username' => 'ddpo.karnal', 'password' => 'secret-pass'])->assertOk();
        $this->postJson('/api/auth/login', ['username' => 'someone.else', 'password' => 'x'])->assertStatus(401);

        $admin = User::factory()->create(['role' => 'super_admin']);

        $all = $this->actingAs($admin, 'sanctum')->getJson('/api/login-logs')->assertOk();
        $all->assertJsonPath('meta.total', 3)
            ->assertJsonPath('logs.0.identifier', 'someone.else')
            ->assertJsonPath('summary.success', 1)
            ->assertJsonPath('summary.failed', 2);

        $this->getJson('/api/login-logs?status=success')
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('logs.0.userName', 'Karnal DDPO')
            ->assertJsonPath('logs.0.userId', $user->id);

        $this->getJson('/api/login-logs?search=Karnal')->assertJsonPath('meta.total', 2);
        $this->getJson('/api/login-logs?status=bogus')->assertUnprocessable();
    }
}
