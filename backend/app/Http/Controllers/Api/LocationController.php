<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\District;
use App\Models\Tehsil;
use App\Models\Village;
use Illuminate\Support\Collection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

class LocationController extends Controller
{
    private function normalizeName(?string $value): string
    {
        $value = mb_strtolower(trim((string) $value));
        $value = preg_replace('/\([^)]*\)/u', ' ', $value) ?? $value;
        $value = preg_replace('/\b(district|tehsil|tahsil|sub[ -]?tehsil|sub[ -]?district)\b/u', ' ', $value) ?? $value;

        return trim(preg_replace('/[^\pL\pN]+/u', ' ', $value) ?? $value);
    }

    private function findByName(Collection $items, array $candidates)
    {
        $normalizedCandidates = collect($candidates)
            ->filter()
            ->map(fn ($value) => $this->normalizeName((string) $value))
            ->filter(fn ($value) => mb_strlen($value) >= 2)
            ->unique()
            ->values();

        foreach ($normalizedCandidates as $candidate) {
            $exact = $items->first(fn ($item) => $this->normalizeName($item->name) === $candidate);
            if ($exact) {
                return $exact;
            }
        }

        foreach ($normalizedCandidates as $candidate) {
            if (mb_strlen($candidate) < 4) {
                continue;
            }
            $partial = $items->first(function ($item) use ($candidate) {
                $name = $this->normalizeName($item->name);

                return str_contains($name, $candidate) || str_contains($candidate, $name);
            });
            if ($partial) {
                return $partial;
            }
        }

        return null;
    }

    private function resolveHierarchy(
        array $districtCandidates,
        array $tehsilCandidates,
        array $villageCandidates,
        ?string $panchayatName = null
    ): array {
        $district = $this->findByName(
            District::query()->orderBy('name')->get(['id', 'name']),
            $districtCandidates
        );

        $tehsil = null;
        $village = null;
        if ($district) {
            $villages = Village::query()
                ->with(['tehsil:id,name,district_id', 'panchayat:id,name'])
                ->whereHas('tehsil', fn ($query) => $query->where('district_id', $district->id))
                ->get(['id', 'name', 'panchayat_id', 'tehsil_id']);
            $village = $this->findByName($villages, $villageCandidates);
            $tehsil = $village?->tehsil ?: $this->findByName(
                Tehsil::where('district_id', $district->id)->get(['id', 'name', 'district_id']),
                $tehsilCandidates
            );
        }

        return [
            'districtId' => $district?->id,
            'district' => $district?->name ?? collect($districtCandidates)->filter()->first(),
            'tehsilId' => $tehsil?->id,
            'tehsil' => $tehsil?->name ?? collect($tehsilCandidates)->filter()->first(),
            'villageId' => $village?->id,
            'village' => $village?->name ?? collect($villageCandidates)->filter()->first(),
            'panchayatId' => $village?->panchayat_id,
            'panchayat' => $village?->panchayat?->name ?? $panchayatName,
        ];
    }

    public function resolve(Request $request): JsonResponse
    {
        $data = $request->validate([
            'district' => ['nullable', 'string', 'max:150'],
            'tehsil' => ['nullable', 'string', 'max:150'],
            'village' => ['nullable', 'string', 'max:150'],
            'panchayat' => ['nullable', 'string', 'max:150'],
        ]);

        if (collect($data)->filter(fn ($value) => trim((string) $value) !== '')->isEmpty()) {
            return response()->json(['success' => false, 'message' => 'Location names are required'], 422);
        }

        return response()->json(['location' => $this->resolveHierarchy(
            [$data['district'] ?? null],
            [$data['tehsil'] ?? null],
            [$data['village'] ?? null],
            $data['panchayat'] ?? null,
        )]);
    }

    public function reverse(Request $request): JsonResponse
    {
        $coordinates = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $latitude = round((float) $coordinates['latitude'], 6);
        $longitude = round((float) $coordinates['longitude'], 6);
        $cacheKey = "reverse-location:v2:{$latitude}:{$longitude}";

        $location = Cache::remember($cacheKey, now()->addDays(30), function () use ($latitude, $longitude) {
            try {
                $response = Http::acceptJson()
                    ->withHeaders([
                        'Accept-Language' => 'en',
                        'User-Agent' => 'MhariPanchayat/1.0 (local-government survey app)',
                    ])
                    ->timeout(10)
                    ->get('https://nominatim.openstreetmap.org/reverse', [
                        'format' => 'jsonv2',
                        'lat' => $latitude,
                        'lon' => $longitude,
                        'addressdetails' => 1,
                        'zoom' => 18,
                    ]);
                $response->throw();
            } catch (\Throwable) {
                return null;
            }
            $address = $response->json('address', []);

            $villageName = $address['village']
                ?? $address['hamlet']
                ?? $address['suburb']
                ?? $address['town']
                ?? $address['city']
                ?? null;

            $districtName = $address['state_district']
                ?? $address['county']
                ?? $address['district']
                ?? null;
            return $this->resolveHierarchy(
                [$districtName, $address['county'] ?? null, $address['district'] ?? null],
                [
                    $address['subdistrict'] ?? null,
                    $address['county'] ?? null,
                    $address['city_district'] ?? null,
                    $address['municipality'] ?? null,
                    $address['town'] ?? null,
                ],
                [$villageName, $address['hamlet'] ?? null, $address['suburb'] ?? null],
                $address['municipality'] ?? $address['city_district'] ?? $villageName,
            );
        });

        return response()->json(['location' => $location]);
    }
}
