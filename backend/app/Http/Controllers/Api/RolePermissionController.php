<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Permission;
use App\Models\RolePermission;
use Illuminate\Http\Request;

class RolePermissionController extends Controller
{
    private const ALL_ROLES = [
        'super_admin', 'state_admin', 'district_admin', 'block_admin', 'department_head',
        'department_officer', 'engineer', 'sarpanch', 'secretary', 'citizen', 'contractor', 'vendor',
    ];

    public function index()
    {
        $permissions = Permission::orderBy('group')->orderBy('label')->get(['key', 'label', 'group']);

        $matrix = RolePermission::with('permission:id,key')
            ->get()
            ->groupBy('role')
            ->map(fn ($rows) => $rows->pluck('permission.key')->values());

        // Every role appears in the matrix even with zero permissions granted.
        foreach (self::ALL_ROLES as $role) {
            if (! isset($matrix[$role])) {
                $matrix[$role] = collect();
            }
        }

        return response()->json([
            'success' => true,
            'roles' => self::ALL_ROLES,
            'permissions' => $permissions,
            'matrix' => $matrix,
        ]);
    }

    public function update(Request $request, string $role)
    {
        if (! in_array($role, self::ALL_ROLES, true)) {
            return response()->json(['success' => false, 'message' => "Unknown role \"{$role}\""], 400);
        }

        $data = $request->validate([
            'permissions' => ['present', 'array'],
            'permissions.*' => ['string', 'exists:permissions,key'],
        ]);

        $permissionIds = Permission::whereIn('key', $data['permissions'])->pluck('id', 'key');

        RolePermission::where('role', $role)
            ->whereNotIn('permission_id', $permissionIds->values())
            ->delete();

        foreach ($permissionIds as $id) {
            RolePermission::firstOrCreate(['role' => $role, 'permission_id' => $id]);
        }

        return response()->json(['success' => true, 'message' => 'Permissions updated', 'permissions' => array_values($data['permissions'])]);
    }
}
