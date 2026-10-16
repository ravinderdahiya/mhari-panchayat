<?php

namespace App\Http\Middleware;

use App\Http\Controllers\Api\AppVersionController;
use App\Models\AppVersion;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Server-side backstop for the app's launch-time version check: a build older
 * than the configured minimum cannot sign in even if the client-side dialog is
 * bypassed. Requests without the X-App-Version-Code header (web, older app
 * builds that predate this check) are left alone.
 */
class CheckAppVersion
{
    private const TTL = 300;

    public function handle(Request $request, Closure $next): Response
    {
        $header = $request->header('X-App-Version-Code');
        if ($header === null || ! ctype_digit((string) $header)) {
            return $next($request);
        }

        $settings = Cache::remember(self::key('android'), self::TTL, function () {
            $version = AppVersion::forPlatform('android');

            return $version
                ? [
                    'min' => $version->min_version_code,
                    'store_url' => $version->store_url,
                    'message' => $version->message ?: AppVersionController::DEFAULT_MESSAGE,
                ]
                : ['min' => 0];
        });

        if ((int) $header < $settings['min']) {
            return response()->json([
                'success' => false,
                'status' => 'force_update',
                'message' => $settings['message'],
                'store_url' => $settings['store_url'] ?? null,
            ], 426);
        }

        return $next($request);
    }

    public static function forgetCache(string $platform): void
    {
        Cache::forget(self::key($platform));
    }

    private static function key(string $platform): string
    {
        return "app_version.min.{$platform}";
    }
}
