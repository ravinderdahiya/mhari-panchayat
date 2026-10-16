<?php

namespace App\Services;

use App\Models\DeviceToken;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Sends push notifications through Firebase Cloud Messaging (HTTP v1).
 *
 * Needs a Firebase service-account JSON; point FIREBASE_CREDENTIALS at it (see
 * config/services.php). Without it every call is a silent no-op, so the in-app
 * inbox keeps working exactly as before on servers that aren't set up yet.
 */
class FcmService
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    /** @var array<string,mixed>|null|false null = not loaded yet, false = unavailable */
    private array|null|false $credentials = null;

    public function enabled(): bool
    {
        return $this->credentials() !== false;
    }

    /**
     * @param array<string,string> $data FCM data values must all be strings.
     */
    public function sendToUser(int $userId, string $title, string $body, array $data = []): void
    {
        if (! $this->enabled()) {
            return;
        }

        $tokens = DeviceToken::where('user_id', $userId)->pluck('token');
        if ($tokens->isEmpty()) {
            return;
        }

        $accessToken = $this->accessToken();
        if ($accessToken === null) {
            return;
        }

        $project = $this->credentials()['project_id'];
        $url = "https://fcm.googleapis.com/v1/projects/{$project}/messages:send";

        foreach ($tokens as $token) {
            $response = Http::withOptions($this->httpOptions())->withToken($accessToken)->timeout(8)->post($url, [
                'message' => [
                    'token' => $token,
                    'notification' => ['title' => $title, 'body' => $body],
                    'data' => array_map('strval', $data),
                    'android' => [
                        'priority' => 'HIGH',
                        'notification' => ['channel_id' => 'mhari_alerts'],
                    ],
                ],
            ]);

            if ($response->successful()) {
                continue;
            }

            // Uninstalled / expired registrations: stop sending to them.
            $status = $response->json('error.status');
            if (in_array($status, ['NOT_FOUND', 'UNREGISTERED', 'INVALID_ARGUMENT'], true)) {
                DeviceToken::where('token', $token)->delete();
            } else {
                Log::warning('FCM send failed', ['status' => $response->status(), 'body' => $response->body()]);
            }
        }
    }

    /**
     * Data-only push to every device subscribed to a topic. No `notification`
     * block on purpose: the app decides on the device whether to show anything
     * (e.g. the update prompt is skipped for users already on the new build).
     *
     * @param array<string,scalar|null> $data FCM data values must all be strings.
     */
    public function sendDataToTopic(string $topic, array $data): bool
    {
        if (! $this->enabled()) {
            return false;
        }

        $accessToken = $this->accessToken();
        if ($accessToken === null) {
            return false;
        }

        $project = $this->credentials()['project_id'];
        $response = Http::withOptions($this->httpOptions())
            ->withToken($accessToken)
            ->timeout(8)
            ->post("https://fcm.googleapis.com/v1/projects/{$project}/messages:send", [
                'message' => [
                    'topic' => $topic,
                    'data' => array_map(fn ($v) => (string) $v, $data),
                    'android' => ['priority' => 'HIGH'],
                ],
            ]);

        if (! $response->successful()) {
            Log::warning('FCM topic send failed', ['status' => $response->status(), 'body' => $response->body()]);
        }

        return $response->successful();
    }

    private function accessToken(): ?string
    {
        return Cache::remember('fcm.access_token', now()->addMinutes(50), function () {
            $c = $this->credentials();
            $now = time();
            $b64 = fn (string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');

            $unsigned = $b64(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])) . '.' . $b64(json_encode([
                'iss' => $c['client_email'],
                'scope' => self::SCOPE,
                'aud' => 'https://oauth2.googleapis.com/token',
                'iat' => $now,
                'exp' => $now + 3600,
            ]));

            if (! openssl_sign($unsigned, $signature, $c['private_key'], OPENSSL_ALGO_SHA256)) {
                Log::warning('FCM: could not sign the service-account JWT');

                return null;
            }

            $response = Http::withOptions($this->httpOptions())->asForm()->timeout(8)->post('https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $unsigned . '.' . $b64($signature),
            ]);

            if (! $response->successful()) {
                Log::warning('FCM: token exchange failed', ['body' => $response->body()]);

                return null;
            }

            return $response->json('access_token');
        });
    }

    /**
     * Some dev machines (PHP on Windows) have no CA bundle configured; point
     * FIREBASE_CA_BUNDLE at one there. Leave it unset on a properly set-up server.
     *
     * @return array<string,mixed>
     */
    private function httpOptions(): array
    {
        $bundle = config('services.firebase.ca_bundle');

        return $bundle ? ['verify' => $bundle] : [];
    }

    /** @return array<string,mixed>|false */
    private function credentials(): array|false
    {
        if ($this->credentials !== null) {
            return $this->credentials;
        }

        $path = config('services.firebase.credentials');
        if (! $path || ! is_file($path)) {
            return $this->credentials = false;
        }

        $json = json_decode((string) file_get_contents($path), true);
        $ok = is_array($json)
            && ! empty($json['project_id'])
            && ! empty($json['client_email'])
            && ! empty($json['private_key']);

        return $this->credentials = $ok ? $json : false;
    }
}
