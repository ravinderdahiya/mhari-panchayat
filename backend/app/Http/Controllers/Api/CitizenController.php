<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CitizenProfile;
use App\Models\Complaint;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CitizenController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'status' => ['sometimes', 'string', 'in:all,active,inactive'],
        ]);

        $query = CitizenProfile::query()
            ->with(['user' => fn ($userQuery) => $userQuery
                ->withCount('complaints')
                ->with(['complaints' => fn ($complaintsQuery) => $complaintsQuery
                    ->with('category:id,name')
                    ->orderByDesc('created_at')])]);

        $search = trim((string) ($data['q'] ?? ''));
        if ($search !== '') {
            $needle = '%'.mb_strtolower($search).'%';
            $query->where(function ($citizenQuery) use ($needle) {
                $citizenQuery
                    ->whereRaw('LOWER(full_name) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(mobile) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(email) LIKE ?', [$needle]);
            });
        }

        $status = $data['status'] ?? 'all';
        if ($status !== 'all') {
            $query->whereHas('user', fn ($userQuery) => $userQuery
                ->where('is_active', $status === 'active'));
        }

        $paginator = $query
            ->orderByDesc('registered_at')
            ->paginate((int) ($data['per_page'] ?? 10));

        $citizens = $paginator->getCollection()
            ->map(fn (CitizenProfile $profile) => [
                'id' => $profile->id,
                'userId' => $profile->user_id,
                'name' => $profile->full_name,
                'mobile' => $profile->mobile,
                'email' => $profile->email,
                'registrationSource' => $profile->registration_source,
                'registeredAt' => $profile->registered_at,
                'lastLoginAt' => $profile->last_login_at,
                'isActive' => (bool) $profile->user?->is_active,
                'location' => $this->locationOf($profile),
                'complaintsCount' => (int) ($profile->user?->complaints_count ?? 0),
                'complaints' => ($profile->user?->complaints ?? collect())->map(fn (Complaint $complaint) => [
                    'id' => $complaint->id,
                    'code' => $complaint->code,
                    'category' => $complaint->category?->name,
                    'status' => $complaint->status,
                    'description' => $complaint->description,
                    'beforePhotoUrl' => $complaint->before_photo_url,
                    'issuePhotoUrls' => $complaint->issue_photo_urls ?? array_values(array_filter([
                        $complaint->before_photo_url,
                    ])),
                    'duringPhotoUrl' => $complaint->during_photo_url,
                    'afterPhotoUrl' => $complaint->after_photo_url,
                    'lat' => $complaint->lat,
                    'long' => $complaint->long,
                    'filedAt' => $complaint->created_at,
                ])->values(),
            ]);

        return response()->json([
            'success' => true,
            'citizens' => $citizens,
            'pagination' => [
                'currentPage' => $paginator->currentPage(),
                'lastPage' => $paginator->lastPage(),
                'perPage' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
            'stats' => [
                'registeredCitizens' => CitizenProfile::query()->count(),
                'activeCitizens' => CitizenProfile::query()
                    ->whereHas('user', fn ($userQuery) => $userQuery->where('is_active', true))
                    ->count(),
                'complaintsFiled' => Complaint::query()
                    ->whereIn('user_id', CitizenProfile::query()->select('user_id'))
                    ->count(),
            ],
        ]);
    }

    /**
     * Called by the citizen app after sign-in. The server resolves the place from the
     * coordinates itself (panchayat boundary first), so the app's text is never trusted.
     */
    public function updateMyLocation(Request $request, LocationController $locations): JsonResponse
    {
        $data = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);
        $profile = CitizenProfile::where('user_id', $request->user()->id)->first();
        if (! $profile) {
            return response()->json(['success' => true, 'saved' => false]);
        }

        $lat = round((float) $data['latitude'], 6);
        $lng = round((float) $data['longitude'], 6);
        $place = $locations->lookup($lat, $lng) ?? [];
        $parts = [$place['village'] ?? null, $place['panchayat'] ?? null, $place['tehsil'] ?? null, $place['block'] ?? null, $place['district'] ?? null, 'Haryana'];

        $profile->update([
            'latitude' => $lat,
            'longitude' => $lng,
            'state' => 'Haryana',
            'district' => $place['district'] ?? null,
            'tehsil' => $place['tehsil'] ?? null,
            'block' => $place['block'] ?? null,
            'panchayat' => $place['panchayat'] ?? null,
            'village' => $place['village'] ?? null,
            'address' => implode(', ', array_values(array_unique(array_filter($parts)))),
            'location_updated_at' => now(),
        ]);

        return response()->json(['success' => true, 'saved' => true]);
    }

    /** Saved device location, or the place of the latest complaint for citizens who have not shared one. */
    private function locationOf(CitizenProfile $profile): ?array
    {
        if ($profile->latitude !== null && $profile->longitude !== null) {
            return [
                'lat' => $profile->latitude, 'long' => $profile->longitude,
                'state' => $profile->state, 'district' => $profile->district, 'tehsil' => $profile->tehsil,
                'block' => $profile->block, 'panchayat' => $profile->panchayat, 'village' => $profile->village,
                'address' => $profile->address, 'source' => 'device', 'updatedAt' => $profile->location_updated_at,
            ];
        }

        $complaint = ($profile->user?->complaints ?? collect())->first(fn ($c) => $c->lat !== null && $c->long !== null);
        if (! $complaint) {
            return null;
        }
        $parts = [$complaint->village, $complaint->panchayat, $complaint->location_tehsil, $complaint->location_block, $complaint->location_district, $complaint->location_state];

        return [
            'lat' => $complaint->lat, 'long' => $complaint->long,
            'state' => $complaint->location_state, 'district' => $complaint->location_district, 'tehsil' => $complaint->location_tehsil,
            'block' => $complaint->location_block, 'panchayat' => $complaint->panchayat, 'village' => $complaint->village,
            'address' => implode(', ', array_values(array_unique(array_filter($parts)))) ?: null,
            'source' => 'complaint', 'updatedAt' => $complaint->created_at,
        ];
    }

    public function destroy(CitizenProfile $citizen): JsonResponse
    {
        $user = $citizen->user;

        if ($user) {
            $user->delete();
        } else {
            $citizen->delete();
        }

        return response()->json([
            'success' => true,
            'message' => 'Citizen deleted successfully.',
        ]);
    }
}
