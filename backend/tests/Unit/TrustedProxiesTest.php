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

    public function test_nothing_is_trusted_by_default(): void
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

    public function test_a_forwarded_header_is_ignored_when_no_proxy_is_trusted(): void
    {
        Route::get('/_ip', fn (Request $request) => $request->ip());

        $this->withServerVariables(['REMOTE_ADDR' => '10.9.9.9'])
            ->get('/_ip', ['X-Forwarded-For' => '203.0.113.7'])
            ->assertSee('10.9.9.9');
    }
}
