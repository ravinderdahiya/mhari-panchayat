<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetType;
use App\Models\Block;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\Designation;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\Permission;
use App\Models\Role;
use App\Models\RolePermission;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\User;
use App\Models\Village;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

// One controller reused for every master-data entity (mirrors the Node
// backend's generic-crud.js factory) instead of ~9 near-identical
// controllers. Reading the list is open to any authenticated user (every
// role needs these for dropdowns); create/update/delete is admin
// only, enforced by the `role:admin` middleware on those routes.
class MasterDataController extends Controller
{
    private const ENTITIES = [
        'states' => ['model' => State::class, 'with' => []],
        'districts' => ['model' => District::class, 'with' => ['state']],
        'tehsils' => ['model' => Tehsil::class, 'with' => ['district']],
        'blocks' => ['model' => Block::class, 'with' => ['district']],
        'panchayats' => ['model' => Panchayat::class, 'with' => ['block']],
        'villages' => ['model' => Village::class, 'with' => ['panchayat', 'tehsil.district']],
        'departments' => ['model' => Department::class, 'with' => []],
        'designations' => ['model' => Designation::class, 'with' => []],
        'roles' => ['model' => Role::class, 'with' => [], 'search' => ['name', 'full_name', 'main_responsibility']],
        'complaint-categories' => ['model' => ComplaintCategory::class, 'with' => ['parent', 'district'], 'orderBy' => 'sort_order'],
        'complaint-priorities' => ['model' => ComplaintPriority::class, 'with' => []],
    ];

    private const COMPLAINT_STATUSES = [
        'Pending', 'Acknowledged', 'Surveyed', 'In_Progress', 'Resolved', 'Rejected', 'Closed', 'Reopened',
    ];

    // Fixed village-infrastructure classification for the GIS asset-tracking
    // module. Each subtype's geometryType is a suggested default only (the
    // frontend pre-selects it but the user can still pick a different one) -
    // not a server-enforced constraint, since the same subtype (e.g. a water
    // tank) is legitimately a point in one village and a mapped polygon in
    // another.
    private const ASSET_CATEGORIES = [
        ['category' => 'Roads & Connectivity', 'subtypes' => [
            ['name' => 'Village link roads (Gram Sadak)', 'geometryType' => 'Line'],
            ['name' => 'Internal streets/gallies', 'geometryType' => 'Line'],
            ['name' => 'PWD/PMGSY roads', 'geometryType' => 'Line'],
            ['name' => 'Bridges/culverts', 'geometryType' => 'Point'],
            ['name' => 'Foot bridges', 'geometryType' => 'Line'],
        ]],
        ['category' => 'Water Infrastructure', 'subtypes' => [
            ['name' => 'Handpumps', 'geometryType' => 'Point'],
            ['name' => 'Tubewells', 'geometryType' => 'Point'],
            ['name' => 'Water tanks/overhead tanks', 'geometryType' => 'Point'],
            ['name' => 'Pipelines (drinking water supply)', 'geometryType' => 'Line'],
            ['name' => 'Ponds/Talab', 'geometryType' => 'Polygon'],
            ['name' => 'Canals/Nehar', 'geometryType' => 'Line'],
            ['name' => 'Water treatment plants', 'geometryType' => 'Point'],
            ['name' => 'Bore wells', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Drainage & Sanitation', 'subtypes' => [
            ['name' => 'Drains (pucca/kaccha)', 'geometryType' => 'Line'],
            ['name' => 'Soak pits', 'geometryType' => 'Point'],
            ['name' => 'Sewage treatment', 'geometryType' => 'Point'],
            ['name' => 'Public/community toilets', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Electricity & Lighting', 'subtypes' => [
            ['name' => 'Streetlights/solar lights', 'geometryType' => 'Point'],
            ['name' => 'Transformers', 'geometryType' => 'Point'],
            ['name' => 'Electric poles', 'geometryType' => 'Point'],
            ['name' => 'Power lines', 'geometryType' => 'Line'],
            ['name' => 'Substations', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Community Buildings', 'subtypes' => [
            ['name' => 'Panchayat Ghar/Bhawan', 'geometryType' => 'Point'],
            ['name' => 'Community halls (Barat Ghar)', 'geometryType' => 'Point'],
            ['name' => 'Anganwadi centres', 'geometryType' => 'Point'],
            ['name' => 'Primary/secondary schools', 'geometryType' => 'Point'],
            ['name' => 'Health sub-centre/PHC', 'geometryType' => 'Point'],
            ['name' => 'Veterinary hospital', 'geometryType' => 'Point'],
            ['name' => 'Fair price shops (Ration depot)', 'geometryType' => 'Point'],
            ['name' => 'Post office', 'geometryType' => 'Point'],
            ['name' => 'Bank/CSC', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Religious & Public Places', 'subtypes' => [
            ['name' => 'Temples/Mandir', 'geometryType' => 'Point'],
            ['name' => 'Mosque/Gurudwara/Church', 'geometryType' => 'Point'],
            ['name' => 'Cremation ground (Shamshan Ghat)', 'geometryType' => 'Polygon'],
            ['name' => 'Graveyard', 'geometryType' => 'Polygon'],
        ]],
        ['category' => 'Recreation & Sports', 'subtypes' => [
            ['name' => 'Playgrounds', 'geometryType' => 'Polygon'],
            ['name' => 'Parks', 'geometryType' => 'Polygon'],
            ['name' => 'Open gyms/community centres', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Agriculture-related Assets', 'subtypes' => [
            ['name' => 'Grain storage/godowns', 'geometryType' => 'Point'],
            ['name' => 'Mandi/collection centres', 'geometryType' => 'Point'],
            ['name' => 'Irrigation channels', 'geometryType' => 'Line'],
            ['name' => 'Common land (Shamlat)', 'geometryType' => 'Polygon'],
            ['name' => 'Chak roads', 'geometryType' => 'Line'],
        ]],
        ['category' => 'Waste Management', 'subtypes' => [
            ['name' => 'Garbage collection points', 'geometryType' => 'Point'],
            ['name' => 'Waste segregation sheds', 'geometryType' => 'Point'],
            ['name' => 'Compost pits', 'geometryType' => 'Point'],
        ]],
        ['category' => 'Boundary & Administrative', 'subtypes' => [
            ['name' => 'Village boundary', 'geometryType' => 'Polygon'],
            ['name' => 'Ward boundaries', 'geometryType' => 'Polygon'],
            ['name' => 'Land use zones', 'geometryType' => 'Polygon'],
        ]],
    ];

    private function resolve(string $entity): array
    {
        if (! isset(self::ENTITIES[$entity])) {
            abort(404, "Unknown master entity \"{$entity}\"");
        }

        return self::ENTITIES[$entity];
    }

    public function index(Request $request, string $entity)
    {
        $config = $this->resolve($entity);
        $paginated = $request->boolean('paginated');

        // Unpaginated callers (mobile/dropdown/filter consumers) only ever read
        // id/name/foreign-key columns, never the relation objects - eager-loading
        // them here was adding seconds to the villages list (7k+ rows x 2 joins)
        // for data nobody rendered. The admin CRUD table is the only relation
        // consumer and always requests `paginated`, so it keeps the eager load.
        $with = $paginated ? $config['with'] : [];
        $query = $config['model']::with($with);
        if ($entity === 'roles') {
            $query->orderByDesc('is_super_admin')->orderBy('name');
        } else {
            $query->orderBy($config['orderBy'] ?? 'name');
        }

        if (! $paginated) {
            // Dropdown/filter consumers should only be offered active entries.
            // The admin CRUD table (paginated) still needs every row so
            // inactive ones can be seen and reactivated.
            return response()->json(['success' => true, 'items' => $query->where('is_active', true)->get()]);
        }

        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $columns = $config['search'] ?? ['name'];
            $query->where(function ($searchQuery) use ($columns, $search) {
                foreach ($columns as $index => $column) {
                    $method = $index === 0 ? 'where' : 'orWhere';
                    $searchQuery->{$method}($column, 'ilike', '%'.$search.'%');
                }
            });
        }

        $status = $request->query('status');
        if (in_array($status, ['active', 'inactive'], true)) {
            $query->where('is_active', $status === 'active');
        }

        $perPage = max(5, min(100, $request->integer('per_page', 10)));
        $paginator = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'items' => $paginator->items(),
            'pagination' => [
                'currentPage' => $paginator->currentPage(),
                'lastPage' => $paginator->lastPage(),
                'perPage' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
            'counts' => [
                'all' => $config['model']::count(),
                'active' => $config['model']::where('is_active', true)->count(),
                'inactive' => $config['model']::where('is_active', false)->count(),
            ],
        ]);
    }

    public function store(Request $request, string $entity)
    {
        $config = $this->resolve($entity);

        try {
            $payload = $entity === 'roles' ? $this->validatedRole($request) : $request->all();
            if ($entity === 'roles' && ! empty($payload['is_super_admin'])) {
                Role::query()->update(['is_super_admin' => false]);
            }
            $item = $config['model']::create($payload);
            $item->load($config['with']);
            if ($entity === 'roles') {
                $this->grantDefaultPermissions($item->name);
                if ($item->is_super_admin) {
                    foreach (Permission::pluck('id') as $permissionId) {
                        RolePermission::firstOrCreate(['role' => $item->name, 'permission_id' => $permissionId]);
                    }
                }
            }
        } catch (QueryException $e) {
            return response()->json(['success' => false, 'message' => 'Could not create', 'error' => $e->getMessage()], 400);
        }

        return response()->json(['success' => true, 'item' => $item], 201);
    }

    public function update(Request $request, string $entity, int $id)
    {
        $config = $this->resolve($entity);
        $item = $config['model']::findOrFail($id);

        try {
            if ($entity === 'roles') {
                $this->updateRoleRecord($item, $request);
            } else {
                $item->update($request->all());
                $item->load($config['with']);
            }
        } catch (QueryException $e) {
            return response()->json(['success' => false, 'message' => 'Could not update', 'error' => $e->getMessage()], 400);
        }

        if ($entity === 'departments') {
            $this->syncAssetTypeStatus($item);
        }

        return response()->json(['success' => true, 'item' => $item]);
    }

    // An asset type stays active as long as at least one of its linked
    // departments is active. Deactivating a department can therefore push a
    // now-orphaned-of-active-departments asset type to inactive too, and
    // reactivating one can bring it back - without overriding an asset type
    // that an admin deliberately deactivated while it still has another
    // active department.
    private function syncAssetTypeStatus(Department $department): void
    {
        $department->assetTypes->each(function (AssetType $assetType) {
            $shouldBeActive = $assetType->departments()->where('is_active', true)->exists();
            if ($assetType->is_active !== $shouldBeActive) {
                $assetType->update(['is_active' => $shouldBeActive]);
            }
        });
    }

    public function destroy(string $entity, int $id)
    {
        $config = $this->resolve($entity);
        $item = $config['model']::findOrFail($id);

        if ($entity === 'roles') {
            return $this->destroyRole($item);
        }

        try {
            $item->delete();
        } catch (QueryException $e) {
            return response()->json(['success' => false, 'message' => 'Could not delete - it may still be referenced elsewhere', 'error' => $e->getMessage()], 400);
        }

        return response()->json(['success' => true, 'message' => 'Deleted']);
    }

    /** @return array{name: string, is_active?: bool} */
    private function validatedRole(Request $request, ?int $ignoreId = null): array
    {
        $request->merge(['name' => $this->slugifyRoleName((string) $request->input('name', ''))]);

        $unique = Rule::unique('roles', 'name');
        if ($ignoreId !== null) {
            $unique->ignore($ignoreId);
        }

        $data = $request->validate([
            'name' => ['required', 'string', 'max:64', 'regex:/^[a-z][a-z0-9_]*$/', $unique],
            'full_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'main_responsibility' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'is_active' => ['sometimes', 'boolean'],
            'is_super_admin' => ['sometimes', 'boolean'],
        ]);
        foreach (['full_name', 'main_responsibility'] as $field) {
            if (array_key_exists($field, $data) && $data[$field] === '') {
                $data[$field] = null;
            }
        }

        return $data;
    }

    private function slugifyRoleName(string $name): string
    {
        return (string) Str::of($name)
            ->trim()
            ->lower()
            ->replace(' ', '_')
            ->replaceMatches('/[^a-z0-9_]/', '');
    }

    private function updateRoleRecord(Role $item, Request $request): void
    {
        $data = $this->validatedRole($request, $item->id);
        $newName = $data['name'];
        $oldName = $item->name;

        if ($item->is_super_admin) {
            if (array_key_exists('is_active', $data) && ! $data['is_active']) {
                throw ValidationException::withMessages(['is_active' => 'The Super Admin role cannot be deactivated.']);
            }
            if (array_key_exists('is_super_admin', $data) && ! $data['is_super_admin']
                && Role::where('is_super_admin', true)->where('id', '!=', $item->id)->doesntExist()) {
                throw ValidationException::withMessages(['is_super_admin' => 'At least one Super Admin role is required.']);
            }
        }

        DB::transaction(function () use ($item, $data, $oldName, $newName) {
            if (! empty($data['is_super_admin'])) {
                Role::where('id', '!=', $item->id)->update(['is_super_admin' => false]);
            }
            $item->update($data);
            if ($oldName === $newName) {
                return;
            }
            User::where('role', $oldName)->update(['role' => $newName]);
            RolePermission::where('role', $oldName)->update(['role' => $newName]);
            ComplaintCategory::where('resolver_role', $oldName)->update(['resolver_role' => $newName]);
        });
    }

    private function destroyRole(Role $item)
    {
        if ($item->is_super_admin) {
            return response()->json(['success' => false, 'message' => 'The Super Admin role cannot be deleted'], 400);
        }

        if (User::where('role', $item->name)->exists()) {
            return response()->json(['success' => false, 'message' => 'Could not delete - it may still be referenced elsewhere'], 400);
        }

        DB::transaction(function () use ($item) {
            RolePermission::where('role', $item->name)->delete();
            ComplaintCategory::where('resolver_role', $item->name)->update(['resolver_role' => null]);
            $item->delete();
        });

        return response()->json(['success' => true, 'message' => 'Deleted']);
    }

    // New roles get the same baseline grants PermissionSeeder gives every
    // system role, so a user assigned this role can still open the app
    // until an admin tunes the matrix.
    private function grantDefaultPermissions(string $role): void
    {
        $keys = [
            'complaints.file',
            'complaints.view',
            'complaints.view_reports',
            'master_data.view',
        ];

        $permissionIds = Permission::whereIn('key', $keys)->pluck('id');
        foreach ($permissionIds as $id) {
            RolePermission::firstOrCreate(['role' => $role, 'permission_id' => $id]);
        }
    }

    private function referenceItems(Request $request, array $items)
    {
        if (! $request->boolean('paginated')) {
            return response()->json(['success' => true, 'items' => $items]);
        }

        $perPage = max(5, min(100, $request->integer('per_page', 10)));
        $total = count($items);
        $lastPage = max(1, (int) ceil($total / $perPage));
        $currentPage = min(max(1, $request->integer('page', 1)), $lastPage);
        $from = $total === 0 ? null : (($currentPage - 1) * $perPage) + 1;
        $pageItems = array_slice($items, ($currentPage - 1) * $perPage, $perPage);

        return response()->json([
            'success' => true,
            'items' => array_values($pageItems),
            'pagination' => [
                'currentPage' => $currentPage,
                'lastPage' => $lastPage,
                'perPage' => $perPage,
                'total' => $total,
                'from' => $from,
                'to' => $from === null ? null : $from + count($pageItems) - 1,
            ],
        ]);
    }

    public function complaintStatuses(Request $request)
    {
        return $this->referenceItems(
            $request,
            array_map(fn ($status) => ['name' => $status], self::COMPLAINT_STATUSES),
        );
    }

    public function assetCategories()
    {
        return response()->json(['success' => true, 'categories' => self::ASSET_CATEGORIES]);
    }
}
