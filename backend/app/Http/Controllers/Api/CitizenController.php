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
            ->with(['user' => fn ($userQuery) => $userQuery->withCount('complaints')]);

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
                'complaintsCount' => (int) ($profile->user?->complaints_count ?? 0),
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
