<?php

namespace App\Http\Controllers\Concerns;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

// {success, message, data} / {success:false, message, errors} envelope plus the
// shared ?bbox= parser used by the polygon endpoints.
trait RespondsWithEnvelope
{
    protected function ok(mixed $data, string $message, int $status = 200): JsonResponse
    {
        return response()->json(['success' => true, 'message' => $message, 'data' => $data], $status);
    }

    /** @param array<string, mixed> $errors */
    protected function fail(string $message, array $errors, int $status): JsonResponse
    {
        $body = ['success' => false, 'message' => $message];
        if ($errors) {
            $body['errors'] = $errors;
        }

        return response()->json($body, $status);
    }

    /** @return array{0: float, 1: float, 2: float, 3: float}|null  minLng,minLat,maxLng,maxLat */
    protected function parseBbox(Request $request): ?array
    {
        $raw = $request->query('bbox');
        if ($raw === null || $raw === '') {
            return null;
        }

        $parts = explode(',', (string) $raw);
        $valid = count($parts) === 4 && count(array_filter($parts, 'is_numeric')) === 4;
        if ($valid) {
            [$minLng, $minLat, $maxLng, $maxLat] = array_map('floatval', $parts);
            $valid = $minLng >= -180 && $maxLng <= 180 && $minLat >= -90 && $maxLat <= 90
                && $minLng < $maxLng && $minLat < $maxLat;
        }

        if (! $valid) {
            abort($this->fail('Validation failed', ['bbox' => ['bbox must be minLng,minLat,maxLng,maxLat within valid ranges.']], 422));
        }

        return [$minLng, $minLat, $maxLng, $maxLat];
    }
}
