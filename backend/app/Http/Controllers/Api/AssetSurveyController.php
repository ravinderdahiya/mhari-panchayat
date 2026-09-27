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
        'assetType:id,name,icon_key,requires_technical_review',
        'reviewedBy:id,name,username',
    ];

    // Every in-flight stage (CPLO/surveyor's own submission included) is a
    // review-then-forward pair: the actor marks their own work reviewed
    // (not yet visible to the next role) before a separate, explicit action
    // actually hands it on. CEO-ZP has no "forward" (nothing sits above
    // them), so `finalApprove` stays the one exception with no _reviewed
    // stage of its own.
    private const REVIEW_STATUSES = [
        'submitted', 'pending', 'returned',
        'gram_sachiv_reviewed', 'gram_sachiv_approved',
        'bdpo_reviewed', 'bdpo_forwarded',
        'ddpo_reviewed', 'ddpo_approved',
        'xen_reviewed', 'xen_forwarded',
        'approved', 'rejected',
    ];

    // CPLO/surveyor submits (created at 'submitted') -> forwardSubmission ->
    // Gram Sachiv reviews (verify) -> forwards (gramSachivForward) ->
    // BDPO reviews (bdpoReview) -> forwards (forward) ->
    // DDPO reviews (ddpoReview) -> forwards (approve) ->
    // [technical asset types only] XEN-PR reviews (technicalReview) ->
    // forwards (xenForward) -> CEO-ZP gives final approval (finalApprove,
    // from either 'ddpo_approved' direct or 'xen_forwarded').
    // `reject`'s role is resolved dynamically (whichever role currently owns
    // the survey's stage may reject it), so it has no fixed 'role' entry.
    private const TRANSITIONS = [
        'forwardSubmission' => ['from' => 'submitted', 'to' => 'pending', 'role' => null],

        'verify' => ['from' => 'pending', 'to' => 'gram_sachiv_reviewed', 'role' => 'gram_sachiv'],
        'return' => ['from' => ['pending', 'gram_sachiv_reviewed'], 'to' => 'returned', 'role' => 'gram_sachiv'],
        'gramSachivForward' => ['from' => 'gram_sachiv_reviewed', 'to' => 'gram_sachiv_approved', 'role' => 'gram_sachiv'],

        'bdpoReview' => ['from' => 'gram_sachiv_approved', 'to' => 'bdpo_reviewed', 'role' => 'bdpo'],
        'forward' => ['from' => 'bdpo_reviewed', 'to' => 'bdpo_forwarded', 'role' => 'bdpo'],

        'ddpoReview' => ['from' => 'bdpo_forwarded', 'to' => 'ddpo_reviewed', 'role' => 'ddpo'],
        'approve' => ['from' => 'ddpo_reviewed', 'to' => 'ddpo_approved', 'role' => 'ddpo'],

        'technicalReview' => ['from' => 'ddpo_approved', 'to' => 'xen_reviewed', 'role' => 'xen_pr'],
        'xenForward' => ['from' => 'xen_reviewed', 'to' => 'xen_forwarded', 'role' => 'xen_pr'],

        'finalApprove' => ['from' => ['ddpo_approved', 'xen_forwarded'], 'to' => 'approved', 'role' => 'ceo_zp'],

        'reject' => ['from' => [
            'pending', 'gram_sachiv_reviewed', 'gram_sachiv_approved',
            'bdpo_reviewed', 'bdpo_forwarded', 'ddpo_reviewed', 'ddpo_approved',
            'xen_reviewed', 'xen_forwarded',
        ], 'to' => 'rejected', 'role' => null],
    ];

    // The role that owns each in-flight status, used to resolve `reject`'s
    // actor requirement dynamically from the survey's current stage. Both
    // halves of a role's review-then-forward pair map to that same role.
    // 'submitted' and 'ddpo_approved' are intentionally absent: 'submitted'
    // is the surveyor's own draft (ensureStageActor() checks ownership
    // directly, not a fixed role), and 'ddpo_approved' branches by asset
    // type (see stageOwnerRole()).
    private const STAGE_OWNER = [
        'pending' => 'gram_sachiv',
        'gram_sachiv_reviewed' => 'gram_sachiv',
        'gram_sachiv_approved' => 'bdpo',
        'bdpo_reviewed' => 'bdpo',
        'bdpo_forwarded' => 'ddpo',
        'ddpo_reviewed' => 'ddpo',
        'xen_reviewed' => 'xen_pr',
        'xen_forwarded' => 'ceo_zp',
    ];

    private function requiresTechnicalReview(AssetSurvey $survey): bool
    {
        return (bool) ($survey->assetType?->requires_technical_review ?? true);
    }

    // 'ddpo_approved' branches: XEN-PR owns it for asset types that need
    // technical review, CEO-ZP owns it directly for ones that don't.
    private function stageOwnerRole(AssetSurvey $survey): ?string
    {
        if ($survey->review_status === 'ddpo_approved') {
            return $this->requiresTechnicalReview($survey) ? 'xen_pr' : 'ceo_zp';
        }

        return self::STAGE_OWNER[$survey->review_status] ?? null;
    }

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

    /** @return list<int> */
    private function allowedPanchayatIds($user): array
    {
        $ids = $user->panchayats()->pluck('panchayats.id')->all();
        if ($user->panchayat_id) {
            $ids[] = (int) $user->panchayat_id;
        }

        return array_values(array_unique(array_filter($ids)));
    }

    private function normalizePanchayatName(?string $value): string
    {
        $value = mb_strtolower(trim((string) $value));

        return trim((string) preg_replace('/\s+/u', ' ', $value));
    }

    private function ensureAssignedPanchayat(Request $request, array $data): void
    {
        $user = $request->user();
        $allowed = $this->allowedPanchayatIds($user);
        if ($allowed === []) {
            if ($user->role === 'cplo') {
                throw ValidationException::withMessages([
                    'panchayat' => 'आपकी पंचायत assigned नहीं है। सर्वे केवल assigned पंचायत में ही किया जा सकता है।',
                ]);
            }

            return;
        }

        $assigned = Panchayat::query()->whereIn('id', $allowed)->get(['id', 'name']);
        $submitted = $this->normalizePanchayatName($data['panchayat'] ?? null);
        $nameOk = $assigned->contains(
            fn ($panchayat) => $this->normalizePanchayatName($panchayat->name) === $submitted
        );
        if ($submitted !== '' && ! $nameOk) {
            throw ValidationException::withMessages([
                'panchayat' => 'Survey allowed only in your assigned panchayat: '.$assigned->pluck('name')->join(', '),
            ]);
        }

        $latitude = isset($data['latitude']) ? (float) $data['latitude'] : null;
        $longitude = isset($data['longitude']) ? (float) $data['longitude'] : null;
        if ($latitude === null || $longitude === null) {
            throw ValidationException::withMessages([
                'panchayat' => 'GPS लोकेशन अनिवार्य है। सर्वे केवल assigned पंचायत में ही किया जा सकता है।',
            ]);
        }

        $detected = app(LocationController::class)->lookup($latitude, $longitude);
        $detectedId = is_array($detected) && isset($detected['panchayatId'])
            ? (int) $detected['panchayatId']
            : 0;
        $detectedName = $this->normalizePanchayatName(
            is_array($detected) ? ($detected['panchayat'] ?? null) : null
        );
        $idMatch = $detectedId > 0 && in_array($detectedId, $allowed, true);
        $detectedNameOk = $detectedName !== '' && $assigned->contains(
            fn ($panchayat) => $this->normalizePanchayatName($panchayat->name) === $detectedName
        );
        $resolved = $detectedId > 0 || $detectedName !== '';

        if (! $resolved || (! $idMatch && ! $detectedNameOk)) {
            throw ValidationException::withMessages([
                'panchayat' => 'आप अपनी निर्धारित पंचायत ('.$assigned->pluck('name')->join(', ').') के क्षेत्र से बाहर हैं। सर्वे केवल assigned पंचायत में ही किया जा सकता है।',
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
            'requiresTechnicalReview' => $this->requiresTechnicalReview($survey),
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
            $query->whereIn('panchayat_id', $this->allowedPanchayatIds($user) ?: [0]);
        } elseif ($user->role === 'bdpo') {
            $blockIds = $user->blocks()->pluck('blocks.id')->all();
            if ($user->block_id) {
                $blockIds[] = $user->block_id;
            }
            $query->whereIn('block_id', $blockIds ?: [0]);
        } elseif ($user->role === 'ddpo') {
            $query->where('district_id', $user->district_id ?: 0);
        } elseif ($user->role === 'xen_pr') {
            // Only ever actionable on 'ddpo_approved' surveys whose asset
            // type actually needs technical review - other statuses (their
            // own forwarded/history) still show regardless.
            $query->where('district_id', $user->district_id ?: 0)
                ->where(function ($jurisdiction) {
                    $jurisdiction->where('review_status', '!=', 'ddpo_approved')
                        ->orWhereHas('assetType', fn ($assetType) => $assetType->where('requires_technical_review', true));
                });
        } elseif ($user->role === 'ceo_zp') {
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

        if ($user->role === 'gram_sachiv' && ! in_array($survey->panchayat_id, $this->allowedPanchayatIds($user), true)) {
            abort(403, 'You can only view surveys from your own panchayat.');
        }

        if ($user->role === 'bdpo' && $survey->block_id !== $user->block_id
            && ! $user->blocks()->whereKey($survey->block_id)->exists()) {
            abort(403, 'You can only view surveys from your own block.');
        }

        if (in_array($user->role, ['ddpo', 'xen_pr', 'ceo_zp'], true) && $survey->district_id !== $user->district_id) {
            abort(403, 'You can only view surveys from your own district.');
        }

        return response()->json(['success' => true, 'survey' => $this->mapSurvey($request, $survey)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate($this->rules(true));
        $this->ensureSurveyScope($request, (int) $data['departmentId'], (int) $data['assetTypeId']);
        $this->ensureAssignedPanchayat($request, $data);
        $photoPaths = $this->storePhotos($request);

        $survey = DB::transaction(function () use ($request, $data, $photoPaths) {
            $panchayat = Panchayat::with('block.district')->find($request->user()->panchayat_id);

            $survey = AssetSurvey::create([
                'surveyor_id' => $request->user()->id,
                'panchayat_id' => $panchayat?->id,
                'block_id' => $panchayat?->block_id,
                'district_id' => $panchayat?->block?->district_id,
                'department_id' => $data['departmentId'],
                'asset_type_id' => $data['assetTypeId'],
                'asset_name' => $data['assetName'],
                // The mobile app's district field defaults from the phone's
                // reverse-geocoder (see asset_survey_form_screen.dart), which
                // for Haryana often reports the Division name (e.g. "Hisar
                // Division") rather than the actual district - the assigned
                // panchayat's own district (already resolved above for
                // district_id) is authoritative whenever one exists.
                'district' => $panchayat?->block?->district?->name ?? $data['district'],
                'panchayat' => $data['panchayat'],
                'village' => $data['village'],
                'latitude' => $data['latitude'],
                'longitude' => $data['longitude'],
                'condition' => $data['condition'],
                'description' => $data['description'] ?? null,
                'survey_date' => $data['surveyDate'],
                'photo_paths' => $photoPaths,
                // Not yet visible to Gram Sachiv - the surveyor reviews their
                // own entry and explicitly forwards it (forwardSubmission).
                'review_status' => 'submitted',
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
        $this->ensureAssignedPanchayat($request, [
            'panchayat' => $data['panchayat'] ?? $survey->panchayat,
            'latitude' => $data['latitude'] ?? $survey->latitude,
            'longitude' => $data['longitude'] ?? $survey->longitude,
        ]);

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

    // The surveyor (CPLO/surveyor/...) reviews their own submitted survey and
    // explicitly sends it on to Gram Sachiv - the only action they take
    // after submission itself.
    public function forwardSubmission(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'forwardSubmission');
        $this->applyTransition($request, $survey, 'forwardSubmission');

        return response()->json([
            'success' => true,
            'message' => 'Survey forwarded to Gram Sachiv.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // Gram Sachiv reviews a pending survey - not yet forwarded to BDPO
    // (see gramSachivForward()).
    public function verify(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'verify');
        $this->applyTransition($request, $survey, 'verify');

        return response()->json([
            'success' => true,
            'message' => 'Survey reviewed.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // Gram Sachiv sends a pending or already-reviewed survey back to the
    // surveyor for correction.
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

    // Gram Sachiv forwards a reviewed survey on to BDPO.
    public function gramSachivForward(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'gramSachivForward');
        $this->applyTransition($request, $survey, 'gramSachivForward');

        return response()->json([
            'success' => true,
            'message' => 'Survey forwarded to BDPO.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // BDPO reviews a gram-sachiv-forwarded survey - not yet forwarded to
    // DDPO (see forward()).
    public function bdpoReview(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'bdpoReview');
        $this->applyTransition($request, $survey, 'bdpoReview');

        return response()->json([
            'success' => true,
            'message' => 'Survey reviewed.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // BDPO forwards a reviewed survey on to DDPO.
    public function forward(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'forward');
        $this->applyTransition($request, $survey, 'forward');

        return response()->json([
            'success' => true,
            'message' => 'Survey forwarded to DDPO.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // DDPO reviews a bdpo-forwarded survey - not yet approved (see
    // approve()).
    public function ddpoReview(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'ddpoReview');
        $this->applyTransition($request, $survey, 'ddpoReview');

        return response()->json([
            'success' => true,
            'message' => 'Survey reviewed.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // DDPO approves a reviewed survey, sending technical-review asset types
    // on to XEN-PR and everything else straight to CEO-ZP for final
    // approval.
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

    // XEN-PR (Executive Engineer, Panchayati Raj) reviews the technical
    // aspects of a DDPO-approved survey, for asset types that require it -
    // not yet forwarded to CEO-ZP (see xenForward()).
    public function technicalReview(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::with('assetType')->findOrFail($id);
        $this->ensureStageActor($request, $survey, 'technicalReview');
        $this->applyTransition($request, $survey, 'technicalReview');

        return response()->json([
            'success' => true,
            'message' => 'Technical review completed.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // XEN-PR forwards a technically-reviewed survey on to CEO-ZP.
    public function xenForward(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::findOrFail($id);
        $this->ensureStageActor($request, $survey, 'xenForward');
        $this->applyTransition($request, $survey, 'xenForward');

        return response()->json([
            'success' => true,
            'message' => 'Survey forwarded to CEO-ZP.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }

    // CEO-ZP (Chief Executive Officer, Zila Parishad) gives the final
    // sign-off, closing the verification chain.
    public function finalApprove(Request $request, int $id): JsonResponse
    {
        $survey = AssetSurvey::with('assetType')->findOrFail($id);
        $this->ensureStageActor($request, $survey, 'finalApprove');
        $this->applyTransition($request, $survey, 'finalApprove');

        return response()->json([
            'success' => true,
            'message' => 'Survey given final approval.',
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
    // jurisdiction. `forwardSubmission` is the one action with no fixed
    // role - only the survey's own surveyor may take it. Otherwise the
    // actor's role must match the stage that owns $action (verify/return/
    // gramSachivForward -> gram_sachiv, bdpoReview/forward -> bdpo,
    // ddpoReview/approve -> ddpo, technicalReview/xenForward -> xen_pr,
    // reject -> whichever role owns the survey's current status), and the
    // actor's own jurisdiction must cover the survey's.
    private function ensureStageActor(Request $request, AssetSurvey $survey, string $action): void
    {
        $user = $request->user();
        if ($user->isSuperAdmin() || $user->role === 'admin') {
            return;
        }

        if ($action === 'forwardSubmission') {
            if (! $this->isSurveyorRole($user->role) || $survey->surveyor_id !== $user->id) {
                abort(403, 'You can only forward your own submitted surveys.');
            }

            return;
        }

        if ($action === 'technicalReview' && ! $this->requiresTechnicalReview($survey)) {
            abort(422, 'This asset type does not require technical review - it goes straight to CEO-ZP for final approval.');
        }
        if ($action === 'finalApprove' && $survey->review_status === 'ddpo_approved' && $this->requiresTechnicalReview($survey)) {
            abort(422, 'This survey needs XEN-PR technical review before final approval.');
        }

        $requiredRole = self::TRANSITIONS[$action]['role'] ?? $this->stageOwnerRole($survey);

        $allowed = $requiredRole !== null && $user->role === $requiredRole && match ($requiredRole) {
            'gram_sachiv' => in_array($survey->panchayat_id, $this->allowedPanchayatIds($user), true),
            'bdpo' => (bool) $survey->block_id && (
                $survey->block_id === $user->block_id || $user->blocks()->whereKey($survey->block_id)->exists()
            ),
            'ddpo', 'xen_pr', 'ceo_zp' => (bool) $user->district_id && $survey->district_id === $user->district_id,
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
        // 'reviewed'/'forwarded' are reused across stages - actor_role
        // (stored alongside, see below) disambiguates which stage a given
        // row belongs to, same as 'forward' (BDPO) already did before this
        // review/forward split existed.
        $pastTense = match ($action) {
            'forwardSubmission', 'gramSachivForward', 'forward', 'xenForward' => 'forwarded',
            'verify', 'bdpoReview', 'ddpoReview' => 'reviewed',
            'return' => 'returned',
            'approve' => 'approved',
            'technicalReview' => 'technically reviewed',
            'finalApprove' => 'given final approval',
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
