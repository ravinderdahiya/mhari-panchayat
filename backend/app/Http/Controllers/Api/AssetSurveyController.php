<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetSurvey;
use App\Models\AssetSurveyReview;
use App\Models\AssetType;
use App\Models\Panchayat;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class AssetSurveyController extends Controller
{
    private const WITH = [
        'surveyor:id,name,username,email,mobile,employee_id,role',
        'department:id,name,code',
        'assetType:id,name,icon_key',
        'reviewedBy:id,name,username',
    ];

    private const REVIEW_STATUSES = [
        'pending', 'returned', 'gram_sachiv_approved', 'bdpo_forwarded', 'approved', 'rejected',
    ];

    // Gram Sachiv -> BDPO -> DDPO approval chain. `reject`'s role is
    // resolved dynamically (whichever role currently owns the survey's
    // stage may reject it), so it has no fixed 'role' entry here.
    private const TRANSITIONS = [
        'verify' => ['from' => 'pending', 'to' => 'gram_sachiv_approved', 'role' => 'gram_sachiv'],
        'return' => ['from' => 'pending', 'to' => 'returned', 'role' => 'gram_sachiv'],
        'forward' => ['from' => 'gram_sachiv_approved', 'to' => 'bdpo_forwarded', 'role' => 'bdpo'],
        'approve' => ['from' => 'bdpo_forwarded', 'to' => 'approved', 'role' => 'ddpo'],
        'reject' => ['from' => ['pending', 'gram_sachiv_approved', 'bdpo_forwarded'], 'to' => 'rejected', 'role' => null],
    ];

    // The role that owns each in-flight status, used to resolve `reject`'s
    // actor requirement dynamically from the survey's current stage.
    private const STAGE_OWNER = [
        'pending' => 'gram_sachiv',
        'gram_sachiv_approved' => 'bdpo',
        'bdpo_forwarded' => 'ddpo',
    ];

    public function options(): JsonResponse
    {
        return response()->json(['success' => true, 'conditions' => [
            ['value' => 'GOOD', 'label' => 'Good'],
            ['value' => 'FAIR', 'label' => 'Fair'],
            ['value' => 'POOR', 'label' => 'Poor'],
            ['value' => 'DAMAGED', 'label' => 'Damaged'],
        ]]);
    }

    private function isSurveyorRole(string $role): bool
    {
        return in_array($role, ['surveyor', 'cplo', 'department_officer', 'department_head'], true);
    }

    private function ensureSurveyScope(Request $request, int $departmentId, int $assetTypeId): void
    {
        $assetIsLinked = AssetType::query()
            ->whereKey($assetTypeId)
            ->whereHas('departments', fn ($query) => $query->whereKey($departmentId))
            ->exists();

        if (! $assetIsLinked) {
            throw ValidationException::withMessages([
                'assetTypeId' => 'Selected asset type is not linked to this department.',
            ]);
        }

        $user = $request->user();
        if (! $this->isSurveyorRole($user->role)) {
            return;
        }

        $assigned = $user->departments()->whereKey($departmentId)->exists()
            || (int) $user->department_id === $departmentId;
        if (! $assigned) {
            throw ValidationException::withMessages([
                'departmentId' => 'This department is not assigned to you.',
            ]);
        }
    }

    private function rules(bool $creating): array
    {
        $required = $creating ? 'required' : 'sometimes';

        return [
            'departmentId' => [$required, 'integer', 'exists:departments,id'],
            'assetTypeId' => [$required, 'integer', 'exists:asset_types,id'],
            'assetName' => [$required, 'string', 'max:200'],
            'district' => [$required, 'string', 'max:150'],
            'panchayat' => [$required, 'string', 'max:150'],
            'village' => [$required, 'string', 'max:150'],
            'latitude' => [$required, 'numeric', 'between:-90,90'],
            'longitude' => [$required, 'numeric', 'between:-180,180'],
            'condition' => [$required, 'in:GOOD,FAIR,POOR,DAMAGED'],
            'description' => ['nullable', 'string', 'max:5000'],
            'surveyDate' => [$required, 'date'],
            'photos' => [$creating ? 'required' : 'sometimes', 'array', 'min:1', 'max:5'],
            'photos.*' => ['file', 'image', 'max:10240'],
        ];
    }

    private function storePhotos(Request $request): array
    {
        $paths = [];
        foreach ($request->file('photos', []) as $photo) {
            $paths[] = $photo->store('asset-surveys/photos', 'public');
        }

        return $paths;
    }

    private function photoUrl(Request $request, string $path): string
    {
        return rtrim(config('app.url'), '/').'/storage/'.ltrim($path, '/');
    }

    private function mapSurvey(Request $request, AssetSurvey $survey): array
    {
        $survey->loadMissing([...self::WITH, 'reviews.actor:id,name,username,role']);
        $surveyorName = $survey->surveyor?->name ?: $survey->surveyor?->username;

        return [
            'id' => (string) $survey->id,
            'assetId' => $survey->asset_code,
            'departmentId' => (string) $survey->department_id,
            'departmentName' => $survey->department?->name,
            'assetTypeId' => (string) $survey->asset_type_id,
            'assetTypeName' => $survey->assetType?->name,
            'assetTypeIconKey' => $survey->assetType?->icon_key,
            'assetName' => $survey->asset_name,
            'district' => $survey->district,
            'panchayat' => $survey->panchayat,
            'panchayatId' => $survey->panchayat_id,
            'blockId' => $survey->block_id,
            'districtId' => $survey->district_id,
            'village' => $survey->village,
            'latitude' => $survey->latitude,
            'longitude' => $survey->longitude,
            'condition' => $survey->condition,
            'description' => $survey->description,
            'surveyDate' => $survey->survey_date?->toISOString(),
            'photoUrls' => collect($survey->photo_paths ?? [])
                ->map(fn (string $path) => $this->photoUrl($request, $path))
                ->values(),
            'surveyedById' => (string) $survey->surveyor_id,
            'surveyedByName' => $surveyorName,
            'surveyor' => $survey->surveyor ? [
                'id' => $survey->surveyor->id,
                'name' => $surveyorName,
                'username' => $survey->surveyor->username,
                'employeeId' => $survey->surveyor->employee_id,
                'email' => $survey->surveyor->email,
                'mobile' => $survey->surveyor->mobile,
                'role' => $survey->surveyor->role,
            ] : null,
            'department' => $survey->department ? [
                'id' => $survey->department->id,
                'name' => $survey->department->name,
                'code' => $survey->department->code,
            ] : null,
            'assetType' => $survey->assetType ? [
                'id' => $survey->assetType->id,
                'name' => $survey->assetType->name,
                'iconKey' => $survey->assetType->icon_key,
            ] : null,
            'reviewStatus' => $survey->review_status,
            'reviewedByName' => $survey->reviewedBy?->name ?: $survey->reviewedBy?->username,
            'reviewedAt' => $survey->reviewed_at?->toISOString(),
            'rejectionReason' => $survey->rejection_reason,
            'reviews' => $survey->reviews->map(fn (AssetSurveyReview $review) => [
                'actorId' => $review->actor_id,
                'actorName' => $review->actor?->name ?: $review->actor?->username,
                'actorRole' => $review->actor_role,
                'action' => $review->action,
                'remarks' => $review->remarks,
                'createdAt' => $review->created_at?->toISOString(),
            ])->values(),
            'createdAt' => $survey->created_at?->toISOString(),
            'updatedAt' => $survey->updated_at?->toISOString(),
        ];
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $query = AssetSurvey::query();
        if ($this->isSurveyorRole($user->role)) {
            $query->where('surveyor_id', $user->id);
        } elseif ($request->filled('surveyor_id')) {
            $query->where('surveyor_id', $request->integer('surveyor_id'));
        }
        if ($request->filled('department_id')) {
            $query->where('department_id', $request->integer('department_id'));
        }
        if ($request->filled('asset_type_id')) {
            $query->where('asset_type_id', $request->integer('asset_type_id'));
        }

        // Each reviewer stage only ever sees surveys from their own
        // jurisdiction - no jurisdiction assigned means nothing to review
        // yet, not everything. Admin/super_admin stay unrestricted.
        if ($user->role === 'gram_sachiv') {
            $query->where('panchayat_id', $user->panchayat_id ?: 0);
        } elseif ($user->role === 'bdpo') {
            $blockIds = $user->blocks()->pluck('blocks.id')->all();
            if ($user->block_id) {
                $blockIds[] = $user->block_id;
            }
            $query->whereIn('block_id', $blockIds ?: [0]);
        } elseif ($user->role === 'ddpo') {
            $query->where('district_id', $user->district_id ?: 0);
        }

        if (! $request->boolean('paginated')) {
            $reviewStatus = strtolower((string) $request->query('review_status', ''));
            if (in_array($reviewStatus, self::REVIEW_STATUSES, true)) {
                $query->where('review_status', $reviewStatus);
            }

            $surveys = $query->with(self::WITH)
                ->latest('survey_date')
                ->latest('id')
                ->get()
                ->map(fn (AssetSurvey $survey) => $this->mapSurvey($request, $survey));

            return response()->json(['success' => true, 'surveys' => $surveys]);
        }

        $statsQuery = clone $query;
        $stats = [
            'totalSurveys' => (clone $statsQuery)->count(),
            'activeSurveyors' => (clone $statsQuery)->distinct()->count('surveyor_id'),
            'poorDamaged' => (clone $statsQuery)->whereIn('condition', ['POOR', 'DAMAGED'])->count(),
            // Unfiltered by review_status so all tab counts show
            // simultaneously, regardless of which tab is currently open.
            'statusCounts' => collect(self::REVIEW_STATUSES)->mapWithKeys(
                fn (string $status) => [$status => (clone $statsQuery)->where('review_status', $status)->count()]
            ),
        ];

        $search = trim((string) $request->query('q', ''));
        if ($search !== '') {
            $like = '%'.$search.'%';
            $query->where(function ($builder) use ($like) {
                $builder->where('asset_code', 'ilike', $like)
                    ->orWhere('asset_name', 'ilike', $like)
                    ->orWhere('district', 'ilike', $like)
                    ->orWhere('panchayat', 'ilike', $like)
                    ->orWhere('village', 'ilike', $like)
                    ->orWhereHas('surveyor', function ($surveyor) use ($like) {
                        $surveyor->where('name', 'ilike', $like)
                            ->orWhere('username', 'ilike', $like)
                            ->orWhere('employee_id', 'ilike', $like);
                    })
                    ->orWhereHas('department', fn ($department) => $department->where('name', 'ilike', $like))
                    ->orWhereHas('assetType', fn ($assetType) => $assetType->where('name', 'ilike', $like));
            });
        }

        $condition = strtoupper((string) $request->query('condition', ''));
        if (in_array($condition, ['GOOD', 'FAIR', 'POOR', 'DAMAGED'], true)) {
            $query->where('condition', $condition);
        }

        $reviewStatus = strtolower((string) $request->query('review_status', ''));
        if (in_array($reviewStatus, self::REVIEW_STATUSES, true)) {
            $query->where('review_status', $reviewStatus);
        }

        $perPage = max(5, min(100, $request->integer('per_page', 10)));
        $paginator = $query->with(self::WITH)
            ->latest('survey_date')
            ->latest('id')
            ->paginate($perPage);
        $surveys = $paginator->getCollection()
            ->map(fn (AssetSurvey $survey) => $this->mapSurvey($request, $survey));

        return response()->json([
            'success' => true,
            'surveys' => $surveys,
            'pagination' => [
                'currentPage' => $paginator->currentPage(),
                'lastPage' => $paginator->lastPage(),
                'perPage' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
            'stats' => $stats,
        ]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::with(self::WITH)->findOrFail($id);
        $user = $request->user();

        if ($this->isSurveyorRole($user->role) && $survey->surveyor_id !== $user->id) {
            abort(403, 'You can only view your own surveys.');
        }

        if ($user->role === 'gram_sachiv' && $survey->panchayat_id !== $user->panchayat_id) {
            abort(403, 'You can only view surveys from your own panchayat.');
        }

        if ($user->role === 'bdpo' && $survey->block_id !== $user->block_id
            && ! $user->blocks()->whereKey($survey->block_id)->exists()) {
            abort(403, 'You can only view surveys from your own block.');
        }

        if ($user->role === 'ddpo' && $survey->district_id !== $user->district_id) {
            abort(403, 'You can only view surveys from your own district.');
        }

        return response()->json(['success' => true, 'survey' => $this->mapSurvey($request, $survey)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate($this->rules(true));
        $this->ensureSurveyScope($request, (int) $data['departmentId'], (int) $data['assetTypeId']);
        $photoPaths = $this->storePhotos($request);

        $survey = DB::transaction(function () use ($request, $data, $photoPaths) {
            $panchayat = Panchayat::with('block')->find($request->user()->panchayat_id);

            $survey = AssetSurvey::create([
                'surveyor_id' => $request->user()->id,
                'panchayat_id' => $panchayat?->id,
                'block_id' => $panchayat?->block_id,
                'district_id' => $panchayat?->block?->district_id,
                'department_id' => $data['departmentId'],
                'asset_type_id' => $data['assetTypeId'],
                'asset_name' => $data['assetName'],
                'district' => $data['district'],
                'panchayat' => $data['panchayat'],
                'village' => $data['village'],
                'latitude' => $data['latitude'],
                'longitude' => $data['longitude'],
                'condition' => $data['condition'],
                'description' => $data['description'] ?? null,
                'survey_date' => $data['surveyDate'],
                'photo_paths' => $photoPaths,
            ]);
            $survey->update([
                'asset_code' => 'AST-'.now()->format('Y').'-'.str_pad((string) $survey->id, 6, '0', STR_PAD_LEFT),
            ]);

            return $survey;
        });

        return response()->json([
            'success' => true,
            'message' => 'Survey saved successfully.',
            'survey' => $this->mapSurvey($request, $survey),
        ], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $user = $request->user();
        $isFullAccess = $user->isSuperAdmin() || $user->role === 'admin';
        if ($survey->surveyor_id !== $user->id && ! $isFullAccess) {
            abort(403, 'You can only update your own surveys.');
        }

        $data = $request->validate($this->rules(false));
        $departmentId = (int) ($data['departmentId'] ?? $survey->department_id);
        $assetTypeId = (int) ($data['assetTypeId'] ?? $survey->asset_type_id);
        $this->ensureSurveyScope($request, $departmentId, $assetTypeId);

        $fieldMap = [
            'departmentId' => 'department_id', 'assetTypeId' => 'asset_type_id',
            'assetName' => 'asset_name', 'district' => 'district', 'panchayat' => 'panchayat',
            'village' => 'village', 'latitude' => 'latitude', 'longitude' => 'longitude',
            'condition' => 'condition', 'description' => 'description', 'surveyDate' => 'survey_date',
        ];
        $updates = [];
        foreach ($fieldMap as $input => $column) {
            if (array_key_exists($input, $data)) {
                $updates[$column] = $data[$input];
            }
        }

        if ($request->hasFile('photos')) {
            foreach ($survey->photo_paths ?? [] as $path) {
                Storage::disk('public')->delete($path);
            }
            $updates['photo_paths'] = $this->storePhotos($request);
        }

        // A correction the surveyor makes on a returned survey resubmits it
        // to the front of the chain rather than leaving it stuck as
        // 'returned' forever.
        if ($survey->review_status === 'returned') {
            $updates['review_status'] = 'pending';
        }

        $survey->update($updates);

        return response()->json([
            'success' => true,
            'message' => 'Survey updated successfully.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // Gram Sachiv verifies a pending survey, sending it on to BDPO.
    public function verify(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'verify');
        $this->applyTransition($request, $survey, 'verify');

        return response()->json([
            'success' => true,
            'message' => 'Survey verified.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // Gram Sachiv sends a pending survey back to the surveyor for correction.
    public function returnForCorrection(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'return');
        $data = $request->validate(['reason' => ['required', 'string', 'max:2000']]);
        $this->applyTransition($request, $survey, 'return', $data['reason']);

        return response()->json([
            'success' => true,
            'message' => 'Survey returned for correction.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // BDPO forwards a gram-sachiv-verified survey on to DDPO.
    public function forward(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'forward');
        $this->applyTransition($request, $survey, 'forward');

        return response()->json([
            'success' => true,
            'message' => 'Survey forwarded.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // DDPO gives the final approval.
    public function approve(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'approve');
        $this->applyTransition($request, $survey, 'approve');

        return response()->json([
            'success' => true,
            'message' => 'Survey approved.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // Rejection is available at any in-flight stage, by whichever role
    // currently owns that stage (or admin/super_admin from anywhere).
    public function reject(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'reject');
        $data = $request->validate(['reason' => ['required', 'string', 'max:2000']]);
        $this->applyTransition($request, $survey, 'reject', $data['reason']);

        return response()->json([
            'success' => true,
            'message' => 'Survey rejected.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $this->ensureReviewer($request);
        $survey = AssetSurvey::findOrFail($id);

        foreach ($survey->photo_paths ?? [] as $path) {
            Storage::disk('public')->delete($path);
        }
        $survey->delete();

        return response()->json(['success' => true, 'message' => 'Survey deleted.']);
    }

    // Deleting a survey outright stays an admin-only action, mirroring
    // the sidebar's own adminOnly gate on the Asset Surveys page
    // (Layout.tsx ADMIN_ROLES).
    private function ensureReviewer(Request $request): void
    {
        if (! $request->user()->isSuperAdmin()) {
            abort(403, 'Only Super Admins can review all asset surveys.');
        }
    }

    // admin/super_admin can act at any stage, on any survey, regardless of
    // jurisdiction. Otherwise the actor's role must match the stage that
    // owns $action (verify/return -> gram_sachiv, forward -> bdpo,
    // approve -> ddpo, reject -> whichever role owns the survey's current
    // status), and the actor's own jurisdiction must cover the survey's.
    private function ensureStageActor(Request $request, AssetSurvey $survey, string $action): void
    {
        $user = $request->user();
        if ($user->isSuperAdmin() || $user->role === 'admin') {
            return;
        }

        $requiredRole = self::TRANSITIONS[$action]['role'] ?? self::STAGE_OWNER[$survey->review_status] ?? null;

        $allowed = $requiredRole !== null && $user->role === $requiredRole && match ($requiredRole) {
            'gram_sachiv' => (bool) $user->panchayat_id && $survey->panchayat_id === $user->panchayat_id,
            'bdpo' => (bool) $survey->block_id && (
                $survey->block_id === $user->block_id || $user->blocks()->whereKey($survey->block_id)->exists()
            ),
            'ddpo' => (bool) $user->district_id && $survey->district_id === $user->district_id,
            default => false,
        };

        if (! $allowed) {
            abort(403, 'You do not have permission to review this survey at its current stage.');
        }
    }

    // Validates the survey's current status is a legal starting point for
    // $action, applies the transition, and records one audit-trail row so
    // an earlier stage's reviewer identity survives later stages acting.
    private function applyTransition(Request $request, AssetSurvey $survey, string $action, ?string $reason = null): void
    {
        $config = self::TRANSITIONS[$action];
        $from = (array) $config['from'];
        $pastTense = match ($action) {
            'verify' => 'verified',
            'return' => 'returned',
            'forward' => 'forwarded',
            'approve' => 'approved',
            'reject' => 'rejected',
        };
        if (! in_array($survey->review_status, $from, true)) {
            abort(422, 'This survey is not at a stage where it can be '.$pastTense.'.');
        }

        $user = $request->user();
        $survey->update([
            'review_status' => $config['to'],
            'reviewed_by_id' => $user->id,
            'reviewed_at' => now(),
            'rejection_reason' => in_array($action, ['reject', 'return'], true) ? $reason : null,
        ]);

        AssetSurveyReview::create([
            'survey_id' => $survey->id,
            'actor_id' => $user->id,
            'actor_role' => $user->role,
            'action' => $pastTense,
            'remarks' => $reason,
        ]);
    }
}
