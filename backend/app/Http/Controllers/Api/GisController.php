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
    private const DEFAULT_TOKEN_TTL_MINUTES = 60;

    // Test/candidate replacement for the Panchayat boundary layer, on a separate
    // ArcGIS Enterprise portal (hsac.org.in) from the one below - see the
    // 'hsac_eodb' service config for its own account and token endpoint.
    private const PANCHAYAT_MAPSERVER_URL = 'https://hsac.org.in/server/rest/services/EODB/EODB_HR24/MapServer';

    private const PANCHAYAT_VECTORTILE_URL = 'https://gis.harsac.in/server/rest/services/Hosted/Panchayatadmin/VectorTileServer';

    /**
     * Reverse proxy for the (currently EODB_HR24, test) boundary MapServer.
     * The ArcGIS JS SDK talks to this endpoint (same-origin, so no CORS
     * problem — neither portal sends CORS headers, which blocks the browser
     * calling it directly) and we forward each request server-side with an
     * injected token. Credentials never reach the browser.
     */
    public function proxyPanchayat(Request $request, string $path = ''): Response
    {
        return $this->proxy($request, self::PANCHAYAT_MAPSERVER_URL, 'hsac_eodb', $path);
    }

    /**
     * Same reverse-proxy scheme as proxyPanchayat(), for HARSAC's hosted
     * Panchayat/district boundary VectorTileServer. The style.json this
     * service returns uses paths relative to its own service root (for
     * tiles, sprites, fonts), so proxying just this one wildcard route
     * carries every sub-resource through too.
     */
    public function proxyPanchayatVectorTile(Request $request, string $path = ''): Response
    {
        return $this->proxy($request, self::PANCHAYAT_VECTORTILE_URL, 'harsac_gis', $path);
    }

    private function proxy(Request $request, string $baseUrl, string $serviceKey, string $path): Response
    {
        $token = $this->resolveToken($serviceKey);
        if (! $token) {
            return response('GIS service is not configured or unreachable', 503);
        }

        $url = $baseUrl.($path !== '' ? "/{$path}" : '');
        $query = array_merge($request->query(), ['token' => $token]);

        try {
            $http = Http::timeout(15);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $upstream = $http->get($url, $query);
        } catch (\Throwable $exception) {
            Log::warning('GIS proxy request failed', ['service' => $serviceKey, 'path' => $path, 'reason' => $exception->getMessage()]);

            return response('Could not reach the GIS service', 502);
        }

        return response($upstream->body(), $upstream->status())
            ->header('Content-Type', $upstream->header('Content-Type') ?: 'application/json');
    }

    private function resolveToken(string $serviceKey): ?string
    {
        $username = config("services.{$serviceKey}.username");
        $password = config("services.{$serviceKey}.password");
        if (! $username || ! $password) {
            return null;
        }

        $cacheKey = "gis_token:{$serviceKey}";
        $cached = Cache::get($cacheKey);
        if ($cached) {
            return $cached['token'];
        }

        $ttlMinutes = config("services.{$serviceKey}.token_ttl_minutes", self::DEFAULT_TOKEN_TTL_MINUTES);

        try {
            $http = Http::asForm()->timeout(10);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $response = $http->post(config("services.{$serviceKey}.token_url"), [
                'username' => $username,
                'password' => $password,
                'client' => 'referer',
                'referer' => config("services.{$serviceKey}.referer"),
                'expiration' => $ttlMinutes,
                'f' => 'json',
            ]);

            $data = $response->json();
            if (! $response->successful() || empty($data['token'])) {
                Log::warning('GIS token request failed', ['service' => $serviceKey, 'status' => $response->status(), 'body' => $data]);

                return null;
            }

            Cache::put($cacheKey, $data, now()->addMinutes($ttlMinutes - 5));

            return $data['token'];
        } catch (\Throwable $exception) {
            Log::warning('GIS token request error', ['service' => $serviceKey, 'reason' => $exception->getMessage()]);

            return null;
        }
    }
}
