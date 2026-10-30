<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\GisController;
use App\Http\Controllers\Api\LocationController;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Every Capture-GPS tap calls the GIS boundary service (and Nominatim). When one of them is slow or
 * down, each call used to hold a PHP worker for 10-30 s, so a handful of citizens could freeze the
 * whole API. Calls now give up fast, and once a service has failed it is skipped for a minute.
 */
class GisResilienceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config([
            'services.harsac_gis.username' => 'u',
            'services.harsac_gis.password' => 'p',
            'services.harsac_gis.token_url' => 'https://gis.example/token',
            'services.harsac_gis.referer' => 'https://app.example',
        ]);
        Cache::put('gis_token:harsac_gis', ['token' => 'tok'], now()->addMinutes(30));
    }

    private function gis(): GisController
    {
        return new GisController;
    }

    /** @var list<string> every URL the app tried to call, including ones that then failed */
    private array $urls = [];

    private function fakeResponse(mixed $response): void
    {
        Http::fake(function (Request $request) use ($response) {
            $this->urls[] = $request->url();
            if ($response instanceof Throwable) {
                throw $response;
            }

            return Http::response($response);
        });
    }

    private function fakeDown(): void
    {
        $this->fakeResponse(new ConnectionException('timed out'));
    }

    private function callsTo(string $needle): int
    {
        return count(array_filter($this->urls, fn ($u) => str_contains($u, $needle)));
    }

    private function queryRequests(): int
    {
        return $this->callsTo('/MapServer/1/query');
    }

    public function test_a_failing_gis_query_is_reported_as_unavailable(): void
    {
        $this->fakeDown();

        $this->assertSame('unavailable', $this->gis()->pointStatus(29.1, 75.7)['status']);
    }

    public function test_after_a_failure_the_service_is_skipped_so_workers_are_not_held(): void
    {
        $this->fakeDown();

        $this->gis()->pointStatus(29.1, 75.7);
        $second = $this->gis()->pointStatus(29.2, 75.8);

        $this->assertSame('unavailable', $second['status']);
        $this->assertSame(1, $this->queryRequests(), 'the second call must not wait on the dead service again');
    }

    public function test_the_service_is_tried_again_once_the_pause_is_over(): void
    {
        $this->fakeDown();
        $this->gis()->pointStatus(29.1, 75.7);

        Cache::forget(GisController::BREAKER_KEY);
        $this->gis()->pointStatus(29.1, 75.7);

        $this->assertSame(2, $this->queryRequests());
    }

    public function test_the_pause_lasts_about_a_minute(): void
    {
        $this->assertGreaterThanOrEqual(30, GisController::BREAKER_SECONDS);
        $this->assertLessThanOrEqual(120, GisController::BREAKER_SECONDS);
    }

    public function test_a_normal_no_match_answer_does_not_pause_the_service(): void
    {
        $this->fakeResponse(['features' => []]);

        $this->assertSame('none', $this->gis()->pointStatus(28.6, 77.2)['status']);
        $this->assertSame('none', $this->gis()->pointStatus(28.7, 77.3)['status']);
        $this->assertSame(2, $this->queryRequests());
    }

    public function test_a_match_is_returned_with_the_panchayat(): void
    {
        $this->fakeResponse(['features' => [['attributes' => ['localbodyc' => '123', 'localbodyn' => 'Satrod']]]]);

        $this->assertSame(
            ['status' => 'matched', 'code' => '123', 'name' => 'Satrod'],
            $this->gis()->pointStatus(29.1, 75.7),
        );
    }

    public function test_an_error_body_from_the_service_counts_as_unavailable_and_pauses_it(): void
    {
        $this->fakeResponse(['error' => ['code' => 498, 'message' => 'Invalid token']]);

        $this->assertSame('unavailable', $this->gis()->pointStatus(29.1, 75.7)['status']);
        $this->gis()->pointStatus(29.1, 75.7);
        $this->assertSame(1, $this->queryRequests());
    }

    public function test_point_in_panchayat_returns_null_at_once_while_the_service_is_paused(): void
    {
        Cache::put(GisController::BREAKER_KEY, true, 60);
        Http::fake();

        $this->assertNull($this->gis()->pointInPanchayat(29.1, 75.7));
        Http::assertNothingSent();
    }

    public function test_a_failing_token_request_also_pauses_the_service(): void
    {
        Cache::forget('gis_token:harsac_gis');
        $this->fakeDown();

        $this->assertSame('unavailable', $this->gis()->pointStatus(29.1, 75.7)['status']);
        $before = count($this->urls);
        $this->gis()->pointStatus(29.1, 75.7);

        $this->assertSame($before, count($this->urls), 'no new calls while paused');
    }

    public function test_calls_give_up_quickly(): void
    {
        $this->assertLessThanOrEqual(4, GisController::QUERY_TIMEOUT);
        $this->assertLessThanOrEqual(4, LocationController::NOMINATIM_TIMEOUT);
    }

    public function test_a_failing_nominatim_is_skipped_for_the_next_citizens(): void
    {
        $this->fakeDown();
        $locations = new LocationController;

        $locations->lookup(29.1111, 75.7111);
        $locations->lookup(29.2222, 75.7222);

        $this->assertSame(1, $this->callsTo('nominatim'));
    }
}
