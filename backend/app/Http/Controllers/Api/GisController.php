<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class GisController extends Controller
{
    private const TOKEN_TTL_MINUTES = 60;

    private const PANCHAYAT_MAPSERVER_URL = 'https://gis.harsac.in/server/rest/services/Panchayat/Panchayat/MapServer';

    /**
     * Reverse proxy for HARSAC's token-secured Panchayat/district boundary
     * MapServer. The ArcGIS JS SDK talks to this endpoint (same-origin, so
     * no CORS problem — gis.harsac.in doesn't send CORS headers, which
     * blocks the browser calling it directly) and we forward each request
     * server-side with an injected token. Credentials never reach the browser.
     */
    public function proxyPanchayat(Request $request, string $path = ''): Response
    {
        $token = $this->resolveToken();
        if (! $token) {
            return response('GIS service is not configured or unreachable', 503);
        }

        $url = self::PANCHAYAT_MAPSERVER_URL.($path !== '' ? "/{$path}" : '');
        $query = array_merge($request->query(), ['token' => $token]);

        try {
            $http = Http::timeout(15);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $upstream = $http->get($url, $query);
        } catch (\Throwable $exception) {
            Log::warning('HARSAC GIS proxy request failed', ['path' => $path, 'reason' => $exception->getMessage()]);

            return response('Could not reach the GIS service', 502);
        }

        return response($upstream->body(), $upstream->status())
            ->header('Content-Type', $upstream->header('Content-Type') ?: 'application/json');
    }

    private function resolveToken(): ?string
    {
        $username = config('services.harsac_gis.username');
        $password = config('services.harsac_gis.password');
        if (! $username || ! $password) {
            return null;
        }

        $cached = Cache::get('harsac_gis_token');
        if ($cached) {
            return $cached['token'];
        }

        try {
            $http = Http::asForm()->timeout(10);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $response = $http->post(config('services.harsac_gis.token_url'), [
                'username' => $username,
                'password' => $password,
                'client' => 'referer',
                'referer' => config('services.harsac_gis.referer'),
                'expiration' => self::TOKEN_TTL_MINUTES,
                'f' => 'json',
            ]);

            $data = $response->json();
            if (! $response->successful() || empty($data['token'])) {
                Log::warning('HARSAC GIS token request failed', ['status' => $response->status(), 'body' => $data]);

                return null;
            }

            Cache::put('harsac_gis_token', $data, now()->addMinutes(self::TOKEN_TTL_MINUTES - 5));

            return $data['token'];
        } catch (\Throwable $exception) {
            Log::warning('HARSAC GIS token request error', ['reason' => $exception->getMessage()]);

            return null;
        }
    }
}
