<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetSurvey;
use App\Models\AssetType;
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
        return in_array($role, ['engineer', 'department_officer', 'department_head'], true);
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
        $survey->loadMissing(self::WITH);
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
            'createdAt' => $survey->created_at?->toISOString(),
            'updatedAt' => $survey->updated_at?->toISOString(),
        ];
    }

    public function index(Request $request): JsonResponse
    {
        $query = AssetSurvey::query();
        if ($this->isSurveyorRole($request->user()->role)) {
            $query->where('surveyor_id', $request->user()->id);
        } elseif ($request->filled('surveyor_id')) {
            $query->where('surveyor_id', $request->integer('surveyor_id'));
        }
        if ($request->filled('department_id')) {
            $query->where('department_id', $request->integer('department_id'));
        }
        if ($request->filled('asset_type_id')) {
            $query->where('asset_type_id', $request->integer('asset_type_id'));
        }

        if (! $request->boolean('paginated')) {
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
        if ($this->isSurveyorRole($request->user()->role)
            && $survey->surveyor_id !== $request->user()->id) {
            abort(403, 'You can only view your own surveys.');
        }

        return response()->json(['success' => true, 'survey' => $this->mapSurvey($request, $survey)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate($this->rules(true));
        $this->ensureSurveyScope($request, (int) $data['departmentId'], (int) $data['assetTypeId']);
        $photoPaths = $this->storePhotos($request);

        $survey = DB::transaction(function () use ($request, $data, $photoPaths) {
            $survey = AssetSurvey::create([
                'surveyor_id' => $request->user()->id,
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
        if ($survey->surveyor_id !== $request->user()->id && $request->user()->role !== 'super_admin') {
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
        $survey->update($updates);

        return response()->json([
            'success' => true,
            'message' => 'Survey updated successfully.',
            'survey' => $this->mapSurvey($request, $survey->fresh()),
        ]);
    }
}
