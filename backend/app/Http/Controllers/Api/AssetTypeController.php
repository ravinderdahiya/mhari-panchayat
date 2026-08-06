<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetType;
use App\Models\Department;
use Illuminate\Http\Request;

class AssetTypeController extends Controller
{
    private function assignedDepartmentIds($user): array
    {
        $user->loadMissing('departments');
        $ids = $user->departments->pluck('id')->all();
        if ($user->department_id) {
            $ids[] = (int) $user->department_id;
        }

        return array_values(array_unique(array_filter($ids)));
    }

    private function isScopedRole(string $role): bool
    {
        return in_array($role, ['engineer', 'department_officer', 'department_head'], true);
    }

    private function mapAssetType(AssetType $type): array
    {
        return [
            'id' => (string) $type->id,
            'name' => $type->name,
            'iconKey' => $type->icon_key,
            'sort_order' => $type->sort_order,
            'is_active' => $type->is_active,
            'departments' => $type->departments->map(fn ($d) => [
                'id' => $d->id,
                'name' => $d->name,
                'code' => $d->code,
            ])->values(),
            'department_ids' => $type->departments->pluck('id')->values(),
        ];
    }

    /**
     * Departments the surveyor may pick from (admin-assigned).
     * Admins get the full department list.
     */
    public function departments(Request $request)
    {
        $user = $request->user();

        if ($this->isScopedRole($user->role)) {
            $ids = $this->assignedDepartmentIds($user);
            $departments = $ids === []
                ? collect()
                : Department::query()->whereIn('id', $ids)->where('is_active', true)->orderBy('name')->get(['id', 'name', 'code']);
        } else {
            $departments = Department::query()->where('is_active', true)->orderBy('name')->get(['id', 'name', 'code']);
        }

        return response()->json([
            'success' => true,
            'departments' => $departments,
            'message' => $departments->isEmpty()
                ? 'No departments assigned. Ask admin to assign a department.'
                : null,
        ]);
    }

    /**
     * Asset types for a selected department.
     * Surveyors must pass department_id and it must be one they were assigned.
     */
    public function index(Request $request)
    {
        $user = $request->user();
        $departmentId = $request->integer('department_id') ?: null;

        $query = AssetType::query()
            ->with('departments:id,name,code')
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($this->isScopedRole($user->role)) {
            $assignedIds = $this->assignedDepartmentIds($user);
            if ($assignedIds === []) {
                return response()->json([
                    'success' => true,
                    'assetTypes' => [],
                    'message' => 'No departments assigned. Ask admin to assign a department.',
                ]);
            }

            if (! $departmentId) {
                return response()->json([
                    'success' => false,
                    'message' => 'Select a department first',
                    'assetTypes' => [],
                ], 422);
            }

            if (! in_array($departmentId, $assignedIds, true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Department not assigned to you',
                    'assetTypes' => [],
                ], 403);
            }

            $query->whereHas('departments', fn ($q) => $q->where('departments.id', $departmentId));
        } elseif ($departmentId) {
            $query->whereHas('departments', fn ($q) => $q->where('departments.id', $departmentId));
        }

        $assetTypes = $query->get()->map(fn (AssetType $type) => $this->mapAssetType($type));

        return response()->json([
            'success' => true,
            'assetTypes' => $assetTypes,
        ]);
    }

    /** Admin: full catalog including inactive. */
    public function adminIndex(Request $request)
    {
        $query = AssetType::query()
            ->with('departments:id,name,code')
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($request->filled('department_id')) {
            $departmentId = $request->integer('department_id');
            $query->whereHas('departments', fn ($department) =>
                $department->where('departments.id', $departmentId));
        }

        // Preserve the original response for any existing non-table consumers.
        if (! $request->boolean('paginated')) {
            $items = $query->get()->map(fn (AssetType $type) => $this->mapAssetType($type));

            return response()->json(['success' => true, 'items' => $items]);
        }

        $perPage = max(5, min(100, $request->integer('per_page', 10)));
        $paginator = $query->paginate($perPage);
        $items = $paginator->getCollection()
            ->map(fn (AssetType $type) => $this->mapAssetType($type));

        return response()->json([
            'success' => true,
            'items' => $items,
            'pagination' => [
                'currentPage' => $paginator->currentPage(),
                'lastPage' => $paginator->lastPage(),
                'perPage' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150', 'unique:asset_types,name'],
            'icon_key' => ['nullable', 'string', 'max:50'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'department_ids' => ['required', 'array', 'min:1'],
            'department_ids.*' => ['integer', 'exists:departments,id'],
        ]);

        $type = AssetType::create([
            'name' => $data['name'],
            'icon_key' => $data['icon_key'] ?? 'apartment',
            'sort_order' => $data['sort_order'] ?? 0,
            'is_active' => $data['is_active'] ?? true,
        ]);
        $type->departments()->sync($data['department_ids']);
        $type->load('departments:id,name,code');

        return response()->json(['success' => true, 'item' => $this->mapAssetType($type)], 201);
    }

    public function update(Request $request, int $id)
    {
        $type = AssetType::findOrFail($id);
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:150', 'unique:asset_types,name,'.$id],
            'icon_key' => ['nullable', 'string', 'max:50'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'department_ids' => ['sometimes', 'array', 'min:1'],
            'department_ids.*' => ['integer', 'exists:departments,id'],
        ]);

        $type->fill(collect($data)->except('department_ids')->all());
        $type->save();

        if (array_key_exists('department_ids', $data)) {
            $type->departments()->sync($data['department_ids']);
        }

        $type->load('departments:id,name,code');

        return response()->json(['success' => true, 'item' => $this->mapAssetType($type)]);
    }

    public function destroy(int $id)
    {
        AssetType::findOrFail($id)->delete();

        return response()->json(['success' => true, 'message' => 'Deleted']);
    }
}
