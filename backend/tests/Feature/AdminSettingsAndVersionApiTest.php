<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use App\Models\User;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class AdminSettingsAndVersionApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $this->seed(PermissionSeeder::class);
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => 'admin']);
    }

    public function test_site_settings_are_admin_only(): void
    {
        $this->getJson('/api/site-settings')->assertUnauthorized();

        $this->actingAs(User::factory()->create(['role' => 'sarpanch']), 'sanctum')
            ->getJson('/api/site-settings')->assertForbidden();
    }

    public function test_admin_saves_site_settings_and_the_public_home_reflects_them(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->putJson('/api/site-settings', [
            'helpline' => '1800-000-000',
            'announcement_active' => '1',
            'announcement_title' => 'Gram Sabha on 2 October',
        ])->assertOk()->assertJsonPath('data.helpline', '1800-000-000');

        $home = $this->getJson('/api/public/home')->assertOk();
        $home->assertJsonPath('data.contact.helpline', '1800-000-000')
            ->assertJsonPath('data.announcement.title', 'Gram Sabha on 2 October');
    }

    public function test_announcement_stays_hidden_without_a_title_or_when_switched_off(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->putJson('/api/site-settings', ['announcement_active' => '1', 'announcement_title' => ''])->assertOk();
        $this->getJson('/api/public/home')->assertJsonPath('data.announcement', null);

        Cache::flush();
        $this->actingAs($admin, 'sanctum')->putJson('/api/site-settings', ['announcement_active' => '0', 'announcement_title' => 'Hidden'])->assertOk();
        $this->getJson('/api/public/home')->assertJsonPath('data.announcement', null);
    }

    public function test_announcement_button_link_must_be_http_or_a_site_path(): void
    {
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->putJson('/api/site-settings', ['announcement_cta_url' => 'javascript:alert(1)'])
            ->assertStatus(422)->assertJsonValidationErrors('announcement_cta_url');
        $this->actingAs($admin, 'sanctum')->putJson('/api/site-settings', ['announcement_cta_url' => '/mhari-panchayat/terms-of-service.html'])->assertOk();
    }

    public function test_app_version_rules_minimum_cannot_exceed_latest(): void
    {
        $admin = $this->admin();
        $payload = ['latest_version_code' => 1, 'min_version_code' => 3, 'store_url' => 'https://play.google.com/store/apps/details?id=x'];

        $this->actingAs($admin, 'sanctum')->putJson('/api/app-versions/android', $payload)
            ->assertStatus(422)->assertJsonValidationErrors('min_version_code');

        $this->actingAs($admin, 'sanctum')->putJson('/api/app-versions/android', ['latest_version_code' => 3, 'min_version_code' => 1] + $payload)
            ->assertOk();
        $this->assertSame(3, AppVersion::forPlatform('android')->latest_version_code);
    }

    public function test_version_check_reports_ok_optional_and_force(): void
    {
        AppVersion::updateOrCreate(['platform' => 'android'], ['latest_version_code' => 5, 'min_version_code' => 3, 'store_url' => 'https://example.com']);

        $this->postJson('/api/app/version-check', ['version_code' => 5])->assertOk()->assertJsonPath('status', 'ok');
        $this->postJson('/api/app/version-check', ['version_code' => 4])->assertOk()->assertJsonPath('status', 'optional_update');
        $this->postJson('/api/app/version-check', ['version_code' => 2])->assertOk()->assertJsonPath('status', 'force_update');
        $this->postJson('/api/app/version-check', [])->assertStatus(422);
    }

    public function test_outdated_build_cannot_sign_in_but_unversioned_clients_can_reach_login(): void
    {
        AppVersion::updateOrCreate(['platform' => 'android'], ['latest_version_code' => 5, 'min_version_code' => 3, 'store_url' => 'https://example.com']);

        $this->withHeader('X-App-Version-Code', '2')
            ->postJson('/api/auth/login', ['username' => 'nobody', 'password' => 'wrong'])
            ->assertStatus(426)->assertJsonPath('status', 'force_update');

        // The web admin panel sends no version header and is never blocked by this.
        $this->flushHeaders();
        $this->postJson('/api/auth/login', ['username' => 'nobody', 'password' => 'wrong'])
            ->assertStatus(401);
    }
}
