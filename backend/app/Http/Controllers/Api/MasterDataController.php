<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Block;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\Designation;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\Village;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;

// One controller reused for every master-data entity (mirrors the Node
// backend's generic-crud.js factory) instead of ~9 near-identical
// controllers. Reading the list is open to any authenticated user (every
// role needs these for dropdowns); create/update/delete is super_admin
// only, enforced by the `role:super_admin` middleware on those routes.
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
        'complaint-categories' => ['model' => ComplaintCategory::class, 'with' => ['parent', 'district'], 'orderBy' => 'sort_order'],
        'complaint-priorities' => ['model' => ComplaintPriority::class, 'with' => []],
    ];

    private const ROLES = [
        'super_admin', 'state_admin', 'district_admin', 'block_admin', 'department_head',
        'department_officer', 'engineer', 'sarpanch', 'secretary', 'citizen', 'contractor', 'vendor',
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
        $query = $config['model']::with($with)->orderBy($config['orderBy'] ?? 'name');

        if (! $paginated) {
            return response()->json(['success' => true, 'items' => $query->get()]);
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
        ]);
    }

    public function store(Request $request, string $entity)
    {
        $config = $this->resolve($entity);

        try {
            $item = $config['model']::create($request->all());
            $item->load($config['with']);
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
            $item->update($request->all());
            $item->load($config['with']);
        } catch (QueryException $e) {
            return response()->json(['success' => false, 'message' => 'Could not update', 'error' => $e->getMessage()], 400);
        }

        return response()->json(['success' => true, 'item' => $item]);
    }

    public function destroy(string $entity, int $id)
    {
        $config = $this->resolve($entity);

        try {
            $config['model']::findOrFail($id)->delete();
        } catch (QueryException $e) {
            return response()->json(['success' => false, 'message' => 'Could not delete - it may still be referenced elsewhere', 'error' => $e->getMessage()], 400);
        }

        return response()->json(['success' => true, 'message' => 'Deleted']);
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

    public function roles(Request $request)
    {
        return $this->referenceItems(
            $request,
            array_map(fn ($role) => ['name' => $role], self::ROLES),
        );
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
