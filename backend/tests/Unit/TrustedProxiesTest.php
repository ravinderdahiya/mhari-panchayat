<?php

namespace Tests\Unit;

use App\Support\TrustedProxies;
use Illuminate\Http\Middleware\TrustProxies;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Behind nginx / a load balancer / Cloudflare every request arrives from the proxy's IP. Unless the proxy
 * is trusted, rate limits (throttle:60,1 ...) then share ONE bucket across all visitors.
 */
class TrustedProxiesTest extends TestCase
{
    protected function tearDown(): void
    {
        TrustProxies::flushState();
        parent::tearDown();
    }

    public function test_empty_proxy_setting_disables_trust(): void
    {
        $this->assertNull(TrustedProxies::fromEnv(null));
        $this->assertNull(TrustedProxies::fromEnv(''));
        $this->assertNull(TrustedProxies::fromEnv('   '));
        $this->assertNull(TrustedProxies::fromEnv(false));
    }

    public function test_a_star_trusts_every_proxy(): void
    {
        $this->assertSame('*', TrustedProxies::fromEnv('*'));
        $this->assertSame('*', TrustedProxies::fromEnv(' * '));
    }

    public function test_a_comma_separated_list_becomes_an_array_of_addresses(): void
    {
        $this->assertSame(['10.0.0.1', '192.168.1.0/24'], TrustedProxies::fromEnv('10.0.0.1, 192.168.1.0/24'));
        $this->assertSame(['10.0.0.1'], TrustedProxies::fromEnv('10.0.0.1,,  ,'));
    }

    public function test_the_visitor_ip_is_used_once_the_proxy_is_trusted(): void
    {
        Route::get('/_ip', fn (Request $request) => $request->ip());
        TrustProxies::at(TrustedProxies::fromEnv('*'));

        $this->withServerVariables(['REMOTE_ADDR' => '10.9.9.9'])
            ->get('/_ip', ['X-Forwarded-For' => '203.0.113.7'])
            ->assertSee('203.0.113.7');
    }

    public function test_default_loopback_proxy_uses_the_forwarded_visitor_ip(): void
    {
        // Load the same proxy list as production without relying on the local .env.
        config(['trustedproxy.proxies' => TrustedProxies::fromEnv('127.0.0.1,::1')]);
        Route::get('/_ip', fn (Request $request) => $request->ip());

        foreach (['127.0.0.1', '::1'] as $proxy) {
            $this->withServerVariables(['REMOTE_ADDR' => $proxy])
                ->get('/_ip', ['X-Forwarded-For' => '203.0.113.7'])
                ->assertContent('203.0.113.7');
        }
    }

    public function test_configured_proxy_list_is_used_without_bootstrap_static_state(): void
    {
        TrustProxies::flushState();
        config(['trustedproxy.proxies' => TrustedProxies::fromEnv('10.9.9.9')]);
        Route::get('/_ip', fn (Request $request) => $request->ip());

        $this->withServerVariables(['REMOTE_ADDR' => '10.9.9.9'])
            ->get('/_ip', ['X-Forwarded-For' => '203.0.113.7'])
            ->assertContent('203.0.113.7');
    }

    public function test_loopback_proxy_uses_nearest_untrusted_ip_in_forwarded_chain(): void
    {
        config(['trustedproxy.proxies' => ['127.0.0.1', '::1']]);
        Route::get('/_ip', fn (Request $request) => $request->ip());

        $this->withServerVariables(['REMOTE_ADDR' => '127.0.0.1'])
            ->get('/_ip', ['X-Forwarded-For' => '198.51.100.99, 203.0.113.7'])
            ->assertContent('203.0.113.7');
    }

    public function test_a_forwarded_header_is_ignored_when_no_proxy_is_trusted(): void
    {
        config(['trustedproxy.proxies' => null]);
        Route::get('/_ip', fn (Request $request) => $request->ip());

        $this->withServerVariables(['REMOTE_ADDR' => '10.9.9.9'])
            ->get('/_ip', ['X-Forwarded-For' => '203.0.113.7'])
            ->assertSee('10.9.9.9');
    }

    public function test_untrusted_client_cannot_override_ip_with_forwarded_header(): void
    {
        config(['trustedproxy.proxies' => ['127.0.0.1', '::1']]);
        Route::get('/_ip', fn (Request $request) => $request->ip());

        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.7'])
            ->get('/_ip', ['X-Forwarded-For' => '198.51.100.99'])
            ->assertContent('203.0.113.7');
    }
}
