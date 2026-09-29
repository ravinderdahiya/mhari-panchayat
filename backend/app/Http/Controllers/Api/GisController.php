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
    //private const PANCHAYAT_MAPSERVER_URL = 'https://hsac.org.in/server/rest/services/EODB/EODB_HR24/MapServer';
    private const PANCHAYAT_MAPSERVER_URL = 'https://gis.harsac.in/server/rest/services/Panchayat/MapServer';

    private const PANCHAYAT_VECTORTILE_URL = 'https://gis.harsac.in/server/rest/services/Panchayat/MapServer';

    /**
     * Reverse proxy for the (currently EODB_HR24, test) boundary MapServer.
     * The ArcGIS JS SDK talks to this endpoint (same-origin, so no CORS
     * problem — neither portal sends CORS headers, which blocks the browser
     * calling it directly) and we forward each request server-side with an
     * injected token. Credentials never reach the browser.
     */
    public function proxyPanchayat(Request $request, string $path = ''): Response
    {
        return $this->proxy($request, self::PANCHAYAT_MAPSERVER_URL, 'harsac_gis', $path);
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

    /**
     * Precise point-in-polygon lookup against the real panchayat boundary
     * layer (sublayer 1, panchayat_bnd - same layer the admin dashboard's
     * map overlays) - used by LocationController::lookup() as the geofence
     * check's authoritative source, in place of guessing from a third-party
     * geocoder's fuzzy village-name match. Returns null (caller falls back
     * to name-based matching) on any GIS failure or when the point simply
     * doesn't fall inside any published panchayat polygon.
     *
     * @return array{code: string, name: ?string}|null
     */
    public function pointInPanchayat(float $latitude, float $longitude): ?array
    {
        $token = $this->resolveToken('harsac_gis');
        if (! $token) {
            return null;
        }

        try {
            $http = Http::timeout(15);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $response = $http->get(self::PANCHAYAT_MAPSERVER_URL.'/1/query', [
                'f' => 'json',
                'geometry' => "{$longitude},{$latitude}",
                'geometryType' => 'esriGeometryPoint',
                'inSR' => 4326,
                'spatialRel' => 'esriSpatialRelIntersects',
                'outFields' => 'local_body_code,localbodyname',
                'returnGeometry' => 'false',
                'token' => $token,
            ]);
        } catch (\Throwable $exception) {
            Log::warning('GIS point-in-panchayat query failed', ['reason' => $exception->getMessage()]);

            return null;
        }

        $attributes = $response->json('features.0.attributes');
        if (! $attributes || empty($attributes['local_body_code'])) {
            return null;
        }

        return [
            'code' => (string) $attributes['local_body_code'],
            'name' => $attributes['localbodyname'] ?? null,
        ];
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
            $http = Http::timeout(30)->withHeaders([
                // Token is generated with client=referer; GIS rejects it without this.
                'Referer' => (string) config("services.{$serviceKey}.referer"),
            ]);
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
            $http = Http::asForm()->timeout(30);
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
