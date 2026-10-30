<?php

namespace Tests\Feature;

use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\User;
use App\Models\UserNotification;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Security regression tests: who may call what, whose data a user can reach, what uploads and inputs
 * can do, and how well the sign-in endpoints resist guessing.
 */
class SecurityTest extends TestCase
{
    use RefreshDatabase;

    /** API routes that are deliberately open. A new open route must be added here on purpose. */
    private const PUBLIC_ROUTES = [
        'POST api/app/version-check',
        'POST api/auth/forgot-password/request', 'POST api/auth/forgot-password/reset',
        'POST api/auth/forgot-password/staff/send-otp', 'POST api/auth/forgot-password/staff/verify-reset',
        'POST api/auth/login', 'POST api/auth/register',
        'POST api/auth/resend-otp', 'POST api/auth/send-otp', 'POST api/auth/verify-otp',
        'GET api/gis/panchayat-vector/{path?}', 'GET api/gis/panchayat/{path?}',
        'GET api/public/assets', 'GET api/public/district-performance', 'GET api/public/funds',
        'GET api/public/home', 'GET api/public/search', 'POST api/public/track-complaint',
        'GET api/registrations/blocks', 'GET api/registrations/departments', 'GET api/registrations/districts',
        'POST api/registrations/email/send-link', 'POST api/registrations/email/verify',
        'GET api/registrations/email/verify-link', 'POST api/registrations/officer',
        'GET api/registrations/panchayats', 'POST api/registrations/phone/send-otp',
        'POST api/registrations/phone/verify-otp', 'POST api/registrations/set-password',
        'POST api/registrations/surveyor', 'GET api/registrations/{id}/status',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        $this->seed(PermissionSeeder::class);
    }

    private function citizen(string $mobile = '9876543210'): User
    {
        return User::factory()->create(['role' => 'citizen', 'mobile' => $mobile]);
    }

    private function complaintOf(User $owner): Complaint
    {
        $priority = ComplaintPriority::firstOrCreate(['name' => 'Medium'], ['level' => 2, 'sla_hours' => 72]);

        return Complaint::create([
            'user_id' => $owner->id, 'priority_id' => $priority->id, 'status' => 'Pending',
            'description' => 'Road has a large pothole outside the school.',
        ]);
    }

    /** @return list<\Illuminate\Routing\Route> */
    private function apiRoutes(): array
    {
        return array_values(array_filter(
            iterator_to_array(Route::getRoutes()),
            fn ($route) => str_starts_with($route->uri(), 'api/'),
        ));
    }

    private function key($route): string
    {
        return $route->methods()[0].' '.$route->uri();
    }

    // ---------------------------------------------------------------- access control

    public function test_the_list_of_open_routes_is_exactly_the_approved_one(): void
    {
        $open = [];
        foreach ($this->apiRoutes() as $route) {
            $guarded = collect($route->gatherMiddleware())->contains(fn ($m) => is_string($m) && str_contains($m, 'auth'));
            if (! $guarded) {
                $open[] = $this->key($route);
            }
        }
        sort($open);
        $expected = self::PUBLIC_ROUTES;
        sort($expected);

        $this->assertSame($expected, $open, 'A route without authentication was added or removed - review it, then update PUBLIC_ROUTES.');
    }

    public function test_every_protected_route_refuses_anonymous_callers(): void
    {
        $failures = [];
        foreach ($this->apiRoutes() as $route) {
            $key = $this->key($route);
            if (in_array($key, self::PUBLIC_ROUTES, true) || in_array($route->methods()[0], ['HEAD', 'OPTIONS'], true)) {
                continue;
            }
            // Placeholders that satisfy the route constraints (uuid, platform), so the request reaches the auth check.
            $uri = '/'.preg_replace_callback('/\{(\w+)\??\}/', fn ($m) => match ($m[1]) {
                'uuid' => '3f2b8c1e-5d4a-4e6f-9a7b-1c2d3e4f5a6b',
                'platform' => 'android',
                default => '1',
            }, $route->uri());
            $status = $this->json($route->methods()[0], $uri)->status();
            if ($status !== 401) {
                $failures[] = "{$key} -> {$status}";
            }
        }

        $this->assertSame([], $failures, "Routes that did not answer 401 to an anonymous request:\n".implode("\n", $failures));
    }

    public function test_a_citizen_cannot_reach_admin_only_endpoints(): void
    {
        $citizen = $this->citizen();

        foreach ([
            ['GET', '/api/site-settings'], ['PUT', '/api/site-settings'],
            ['GET', '/api/app-versions'], ['PUT', '/api/app-versions/android'],
            ['GET', '/api/citizens'],
            ['GET', '/api/users'], ['GET', '/api/roles/permissions'], ['PUT', '/api/roles/citizen/permissions'],
        ] as [$method, $uri]) {
            $this->actingAs($citizen, 'sanctum')->json($method, $uri)->assertForbidden();
        }
    }

    public function test_a_citizen_cannot_make_themselves_an_admin_through_their_profile(): void
    {
        $citizen = $this->citizen();

        $this->actingAs($citizen, 'sanctum')->putJson('/api/auth/profile', [
            'name' => 'Mallory', 'role' => 'admin', 'is_active' => true, 'is_super_admin' => true, 'district_id' => 1,
        ]);

        $citizen->refresh();
        $this->assertSame('citizen', $citizen->role);
    }

    // ---------------------------------------------------------------- one user's data from another

    public function test_a_citizen_cannot_open_another_citizens_complaint(): void
    {
        $owner = $this->citizen('9876543210');
        $other = $this->citizen('9123456789');
        $complaint = $this->complaintOf($owner);

        $status = $this->actingAs($other, 'sanctum')->getJson("/api/complaints/{$complaint->id}")->status();

        $this->assertContains($status, [403, 404], "another citizen got HTTP {$status} for someone else's complaint");
    }

    public function test_a_citizen_cannot_read_another_citizens_notifications(): void
    {
        $owner = $this->citizen('9876543210');
        $other = $this->citizen('9123456789');
        UserNotification::create(['user_id' => $owner->id, 'type' => 'COMPLAINT_ACKNOWLEDGED', 'title' => 'Secret title', 'message' => 'm']);

        $body = $this->actingAs($other, 'sanctum')->getJson('/api/notifications')->assertOk()->getContent();

        $this->assertStringNotContainsString('Secret title', $body);
    }

    public function test_a_citizen_cannot_mark_another_citizens_notification_as_read(): void
    {
        $owner = $this->citizen('9876543210');
        $other = $this->citizen('9123456789');
        $note = UserNotification::create(['user_id' => $owner->id, 'type' => 'COMPLAINT_ACKNOWLEDGED', 'title' => 't', 'message' => 'm']);

        $this->actingAs($other, 'sanctum')->patchJson("/api/notifications/{$note->id}/read");

        $this->assertFalse((bool) $note->refresh()->is_read);
    }

    public function test_api_responses_never_contain_password_material(): void
    {
        $user = User::factory()->create(['role' => 'citizen', 'mobile' => '9876543210', 'password' => 'Sup3r-Secret-Pass']);

        $me = $this->actingAs($user, 'sanctum')->getJson('/api/auth/me')->assertOk()->getContent();

        $this->assertStringNotContainsString('Sup3r-Secret-Pass', $me);
        $this->assertStringNotContainsString('login_password', $me);
        $this->assertStringNotContainsString('$2y$', $me);
    }

    public function test_the_public_tracker_does_not_say_whether_a_complaint_exists(): void
    {
        $owner = $this->citizen('9876543210');
        $complaint = $this->complaintOf($owner);

        $wrongMobile = $this->postJson('/api/public/track-complaint', ['complaint_id' => $complaint->code, 'mobile' => '9000000000']);
        $unknown = $this->postJson('/api/public/track-complaint', ['complaint_id' => 'COMP-NOPE-00_0000-001', 'mobile' => '9000000000']);

        $this->assertSame($unknown->status(), $wrongMobile->status());
        $this->assertSame($unknown->json('message'), $wrongMobile->json('message'));
    }

    public function test_the_registration_status_endpoint_does_not_expose_roles_or_rejection_reasons(): void
    {
        $this->markTestIncomplete('OPEN FINDING (low): GET /api/registrations/{id}/status is public and takes sequential ids, so anyone can read the status, role and rejection reason of any registration. Fix needs a decision on how the app proves it owns the registration.');

        $user = User::factory()->create(['role' => 'cplo', 'registration_status' => 'rejected', 'rejection_reason' => 'Fake ID card']);

        $body = $this->getJson("/api/registrations/{$user->id}/status")->getContent();

        $this->assertStringNotContainsString('Fake ID card', $body);
        $this->assertStringNotContainsString('"role"', $body);
    }

    // ---------------------------------------------------------------- hostile input

    public function test_sql_injection_probes_do_not_break_or_widen_the_public_queries(): void
    {
        foreach (["' OR '1'='1", "'; DROP TABLE users; --", '" OR ""="', "1' UNION SELECT password FROM users--", '%', '_', '\\'] as $probe) {
            $this->getJson('/api/public/search?q='.urlencode($probe))->assertOk();
            $this->postJson('/api/public/track-complaint', ['complaint_id' => $probe, 'mobile' => '9876543210'])->assertStatus(404);
        }
        $this->assertDatabaseCount('users', 0);
        $this->assertTrue(\Illuminate\Support\Facades\Schema::hasTable('users'));
    }

    public function test_a_script_file_cannot_be_uploaded_as_a_complaint_photo(): void
    {
        $citizen = $this->citizen();

        $response = $this->actingAs($citizen, 'sanctum')->post('/api/complaints', [
            'description' => 'The village road has a large unsafe pothole.',
            'priority_id' => 1, 'department_id' => 1, 'asset_type_id' => 1, 'district_id' => 1, 'tehsil_id' => 1, 'village_id' => 1,
            'photos' => [UploadedFile::fake()->createWithContent('shell.php.jpg', '<?php system($_GET["c"]); ?>')],
        ], ['Accept' => 'application/json']);

        $response->assertStatus(422);
    }

    public function test_the_voice_note_upload_only_accepts_audio_files(): void
    {
        $citizen = $this->citizen();

        $response = $this->actingAs($citizen, 'sanctum')->post('/api/complaints', [
            'description' => 'The village road has a large unsafe pothole.',
            'priority_id' => 1, 'department_id' => 1, 'asset_type_id' => 1, 'district_id' => 1, 'tehsil_id' => 1, 'village_id' => 1,
            'photos' => [UploadedFile::fake()->createWithContent('p.png', base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))],
            'voice_note' => UploadedFile::fake()->createWithContent('note.php', '<?php system($_GET["c"]); ?>'),
        ], ['Accept' => 'application/json']);

        $response->assertStatus(422)->assertJsonValidationErrors('voice_note');
    }

    public function test_a_real_audio_file_is_still_accepted_as_a_voice_note(): void
    {
        $wav = "RIFF$   WAVEfmt      D¬  X   data    ";

        $this->actingAs($this->citizen(), 'sanctum')->post('/api/complaints', [
            'description' => 'The village road has a large unsafe pothole.',
            'voice_note' => UploadedFile::fake()->createWithContent('note.wav', $wav),
        ], ['Accept' => 'application/json'])->assertJsonMissingValidationErrors('voice_note');
    }

    public function test_ordinary_map_requests_still_go_through_the_proxy(): void
    {
        config([
            'services.harsac_gis.username' => 'u', 'services.harsac_gis.password' => 'p',
            'services.harsac_gis.token_url' => 'https://gis.example/token', 'services.harsac_gis.referer' => 'https://app.example',
        ]);
        Cache::put('gis_token:harsac_gis', ['token' => 'tok'], now()->addMinutes(30));
        $called = [];
        Http::fake(function (HttpRequest $request) use (&$called) {
            $called[] = $request->url();

            return Http::response('{}');
        });

        $this->get('/api/gis/panchayat/1/query?f=json')->assertOk();
        $this->get('/api/gis/panchayat-vector/tile/12/3/4.pbf')->assertOk();
        $this->get('/api/gis/panchayat')->assertOk();

        $this->assertStringContainsString('/Panchayat/MapServer/1/query', $called[0]);
        $this->assertStringContainsString('/tile/12/3/4.pbf', $called[1]);
        $this->assertCount(3, $called);
    }

    public function test_the_public_map_proxy_cannot_be_steered_outside_the_panchayat_service(): void
    {
        config([
            'services.harsac_gis.username' => 'u', 'services.harsac_gis.password' => 'p',
            'services.harsac_gis.token_url' => 'https://gis.example/token', 'services.harsac_gis.referer' => 'https://app.example',
        ]);
        Cache::put('gis_token:harsac_gis', ['token' => 'secret-gis-token'], now()->addMinutes(30));
        $called = [];
        Http::fake(function (HttpRequest $request) use (&$called) {
            $called[] = $request->url();

            return Http::response('{}');
        });

        foreach (['../../Other/MapServer/0/query', '%2e%2e/%2e%2e/Other/MapServer', '..%2f..%2fPrivate/MapServer', 'https://evil.example/x', '/../Other'] as $path) {
            $this->get('/api/gis/panchayat/'.$path);
        }

        foreach ($called as $url) {
            $normalised = preg_replace('#/(?:\.|%2e){1,2}(?=/|$)#i', '/__dot__', $url);
            $this->assertStringContainsString('/Panchayat/MapServer', $url, "proxy left the service: {$url}");
            $this->assertStringNotContainsString('__dot__', $normalised, "proxy forwarded a path-traversal segment: {$url}");
            $this->assertStringNotContainsString('evil.example', $url);
        }
    }

    // ---------------------------------------------------------------- guessing and sessions

    public function test_login_gives_the_same_answer_for_an_unknown_user_and_a_wrong_password(): void
    {
        User::factory()->create(['username' => 'known_user', 'role' => 'sarpanch', 'password' => 'Correct-Horse-1']);

        $wrong = $this->postJson('/api/auth/login', ['username' => 'known_user', 'password' => 'bad-password']);
        $unknown = $this->postJson('/api/auth/login', ['username' => 'no_such_user', 'password' => 'bad-password']);

        $this->assertSame($unknown->status(), $wrong->status());
        $this->assertSame($unknown->json('message'), $wrong->json('message'));
    }

    public function test_repeated_wrong_passwords_are_blocked_in_production(): void
    {
        $this->app->detectEnvironment(fn () => 'production');
        User::factory()->create(['username' => 'known_user', 'role' => 'sarpanch', 'password' => 'Correct-Horse-1']);

        $statuses = [];
        foreach (range(1, 8) as $_) {
            $statuses[] = $this->postJson('/api/auth/login', ['username' => 'known_user', 'password' => 'guess'])->status();
        }

        $this->assertContains(429, $statuses, 'eight wrong passwords in a row were never rate limited');
        $this->assertLessThanOrEqual(5, array_search(429, $statuses), 'the block should start within the first few attempts');
    }

    public function test_repeated_wrong_otps_are_blocked_in_production(): void
    {
        $this->app->detectEnvironment(fn () => 'production');

        $statuses = [];
        foreach (range(1, 14) as $_) {
            $statuses[] = $this->postJson('/api/auth/verify-otp', ['mobile' => '9876543210', 'otp' => (string) random_int(1000, 9999)])->status();
        }

        $this->assertContains(429, $statuses, 'OTP guessing was never rate limited');
    }

    public function test_login_tokens_expire(): void
    {
        $this->markTestIncomplete('OPEN FINDING (medium): Sanctum tokens never expire (sanctum.expiration = null). Pick a lifetime (e.g. 90 days) - users then sign in again by OTP.');

        $this->assertNotNull(config('sanctum.expiration'), 'tokens never expire: a stolen token works forever');
    }

    // A fixed OTP in a developer's own .env is a deployment matter, so check the shipped template instead.
    public function test_the_env_template_does_not_ship_a_fixed_otp(): void
    {
        $template = file_get_contents(base_path('.env.example'));

        $this->assertDoesNotMatchRegularExpression('/^OTP_STATIC_BYPASS_CODE=\S+/m', $template, 'a fixed OTP lets anyone sign in as any citizen');
    }

    public function test_api_responses_carry_basic_hardening_headers(): void
    {
        $response = $this->getJson('/api/public/home');

        $response->assertHeader('X-Content-Type-Options', 'nosniff');
    }
}
