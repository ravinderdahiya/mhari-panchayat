<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetSurvey;
use App\Support\SurveyJurisdiction;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AssetController extends Controller
{
    private const WITH = ['assetType:id,name,icon_key', 'department:id,name,code', 'block:id,name'];

    private function summary(AssetSurvey $survey): array
    {
        return [
            'id' => (string) $survey->id,
            'assetId' => $survey->asset_code,
            'assetName' => $survey->asset_name,
            'assetTypeId' => (string) $survey->asset_type_id,
            'assetTypeName' => $survey->assetType?->name,
            'iconKey' => $survey->assetType?->icon_key,
            'latitude' => $survey->latitude,
            'longitude' => $survey->longitude,
            'condition' => $survey->condition,
        ];
    }

    /**
     * Assets the signed-in user may see on the map. A CPLO works one assigned
     * panchayat, so they only get that area's assets; a reviewer (Gram Sachiv, BDPO,
     * DDPO, XEN-PR, CEO-ZP) only their own jurisdiction, exactly like their survey
     * list. Nobody with no area assigned yet sees anything. Every other role keeps
     * the full set, as before (citizens need it to report an issue on any asset).
     */
    private function visibleAssets(Request $request): Builder
    {
        $query = AssetSurvey::query();
        $user = $request->user();
        if (! $user) {
            return $query;
        }

        if ($user->role === 'cplo') {
            $query->whereIn('panchayat_id', SurveyJurisdiction::panchayatIds($user) ?: [0]);
        } else {
            SurveyJurisdiction::apply($query, $user);
        }

        return $query;
    }

    public function index(Request $request): JsonResponse
    {
        $assets = $this->visibleAssets($request)->with(self::WITH)
            ->latest('survey_date')
            ->get()
            ->map(fn (AssetSurvey $survey) => $this->summary($survey));

        return response()->json(['success' => true, 'assets' => $assets]);
    }

    public function nearby(Request $request): JsonResponse
    {
        $data = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'radius' => ['nullable', 'numeric', 'min:1', 'max:50000'],
        ]);
        $latitude = (float) $data['latitude'];
        $longitude = (float) $data['longitude'];
        $radius = (float) ($data['radius'] ?? 100);

        $assets = $this->visibleAssets($request)->with(self::WITH)->get()
            ->map(function (AssetSurvey $survey) use ($latitude, $longitude) {
                $lat1 = deg2rad($latitude);
                $lat2 = deg2rad($survey->latitude);
                $deltaLat = deg2rad($survey->latitude - $latitude);
                $deltaLng = deg2rad($survey->longitude - $longitude);
                $a = sin($deltaLat / 2) ** 2
                    + cos($lat1) * cos($lat2) * sin($deltaLng / 2) ** 2;
                $distance = 6371000 * 2 * atan2(sqrt($a), sqrt(1 - $a));

                return [...$this->summary($survey), 'distanceMeters' => (int) round($distance)];
            })
            ->filter(fn (array $asset) => $asset['distanceMeters'] <= $radius)
            ->sortBy('distanceMeters')
            ->values();

        return response()->json(['success' => true, 'assets' => $assets]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $survey = $this->visibleAssets($request)->with(self::WITH)->findOrFail($id);
        $photoUrls = collect($survey->photo_paths ?? [])
            ->map(fn (string $path) => '/storage/'.ltrim($path, '/'))
            ->values();

        return response()->json(['success' => true, 'asset' => [
            ...$this->summary($survey),
            'district' => $survey->district,
            'block' => $survey->block?->name ?? '',
            'panchayat' => $survey->panchayat,
            'village' => $survey->village,
            'photoUrls' => $photoUrls,
            'description' => $survey->description,
            'surveyDate' => $survey->survey_date?->toISOString(),
            'totalComplaints' => 0,
            'resolvedCount' => 0,
            'pendingCount' => 0,
        ]]);
    }
}
