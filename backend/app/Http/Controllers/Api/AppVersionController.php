<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Http\Middleware\CheckAppVersion;
use App\Models\AppVersion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AppVersionController extends Controller
{
    use RespondsWithEnvelope;

    public const DEFAULT_MESSAGE = 'A new version of the app is available. Please update.';

    // Public: the app calls this on launch, before anyone is signed in.
    public function check(Request $request): JsonResponse
    {
        $data = $request->validate([
            'version_code' => ['required', 'integer', 'min:0'],
            'platform' => ['nullable', 'in:android,ios'],
        ]);

        $version = AppVersion::forPlatform($data['platform'] ?? 'android');
        if (! $version) {
            return response()->json(['success' => true, 'status' => 'ok']);
        }

        return response()->json([
            'success' => true,
            'status' => $version->statusFor((int) $data['version_code']),
            'latest_code' => $version->latest_version_code,
            'min_code' => $version->min_version_code,
            'store_url' => $version->store_url,
            'message' => $version->message ?: self::DEFAULT_MESSAGE,
        ]);
    }

    // Admin: list the per-platform release settings.
    public function index(): JsonResponse
    {
        return $this->ok(AppVersion::orderBy('platform')->get(), 'App versions');
    }

    public function update(Request $request, string $platform): JsonResponse
    {
        $data = $request->validate([
            'latest_version_code' => ['required', 'integer', 'min:1'],
            'min_version_code' => ['required', 'integer', 'min:1', 'lte:latest_version_code'],
            'store_url' => ['required', 'url', 'max:255'],
            'message' => ['nullable', 'string', 'max:255'],
        ], [
            'min_version_code.lte' => 'The minimum version cannot be higher than the latest version.',
        ]);

        $version = AppVersion::updateOrCreate(['platform' => $platform], $data);
        CheckAppVersion::forgetCache($platform);

        return $this->ok($version, 'App version updated');
    }
}
