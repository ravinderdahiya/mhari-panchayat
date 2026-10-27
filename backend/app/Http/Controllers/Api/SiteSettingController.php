<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Models\SiteSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Admin editing of the public home page content (announcement, helpline, ...). */
class SiteSettingController extends Controller
{
    use RespondsWithEnvelope;

    public function index(): JsonResponse
    {
        return $this->ok(SiteSetting::values(), 'Site settings');
    }

    public function update(Request $request): JsonResponse
    {
        $keys = array_keys(SiteSetting::DEFAULTS);
        $data = $request->validate([
            ...collect($keys)->mapWithKeys(fn ($key) => [$key => ['nullable', 'string', 'max:'.(str_contains($key, 'body') ? 600 : 200)]])->all(),
            'announcement_cta_url' => ['nullable', 'string', 'max:300', 'regex:/^(https?:\/\/|\/)/i'],
        ]);

        foreach ($keys as $key) {
            if (array_key_exists($key, $data)) {
                SiteSetting::updateOrCreate(['key' => $key], ['value' => (string) ($data[$key] ?? '')]);
            }
        }
        SiteSetting::forget();

        return $this->ok(SiteSetting::values(), 'Site settings saved');
    }
}
