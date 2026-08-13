<?php

namespace Database\Seeders;

use App\Models\Permission;
use App\Models\RolePermission;
use Illuminate\Database\Seeder;

// Seeds the exact permission matrix that already existed as hardcoded role
// lists in routes/api.php - flipping the gates from role: to permission:
// changes nothing on day one, it's purely additive until an admin edits a
// checkbox on the Roles page.
class PermissionSeeder extends Seeder
{
    private const ALL_ROLES = [
        'super_admin', 'state_admin', 'district_admin', 'block_admin', 'department_head',
        'department_officer', 'engineer', 'sarpanch', 'secretary', 'citizen', 'contractor', 'vendor',
    ];

    private const PERMISSIONS = [
        ['key' => 'complaints.file', 'label' => 'File complaints', 'group' => 'Complaints', 'roles' => self::ALL_ROLES],
        ['key' => 'complaints.view', 'label' => 'View complaints', 'group' => 'Complaints', 'roles' => self::ALL_ROLES],
        ['key' => 'complaints.view_reports', 'label' => 'View dashboard reports', 'group' => 'Complaints', 'roles' => self::ALL_ROLES],
        ['key' => 'complaints.acknowledge', 'label' => 'Acknowledge complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'block_admin']],
        ['key' => 'complaints.survey', 'label' => 'Submit field survey', 'group' => 'Complaints', 'roles' => ['engineer']],
        ['key' => 'complaints.resolve', 'label' => 'Resolve complaints', 'group' => 'Complaints', 'roles' => ['department_officer', 'department_head', 'super_admin']],
        ['key' => 'complaints.verify', 'label' => 'Verify field reports', 'group' => 'Complaints', 'roles' => ['department_officer', 'department_head', 'super_admin']],
        ['key' => 'complaints.rate', 'label' => 'Rate & close complaints', 'group' => 'Complaints', 'roles' => ['citizen']],
        ['key' => 'complaints.transfer', 'label' => 'Transfer complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'block_admin', 'department_head', 'department_officer', 'super_admin']],
        ['key' => 'complaints.reopen', 'label' => 'Reopen complaints', 'group' => 'Complaints', 'roles' => ['citizen']],
        ['key' => 'complaints.reject', 'label' => 'Reject complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'block_admin', 'department_head', 'department_officer', 'super_admin']],
        ['key' => 'master_data.view', 'label' => 'View master data', 'group' => 'Master Data', 'roles' => self::ALL_ROLES],
        ['key' => 'master_data.manage', 'label' => 'Create/edit/delete master data', 'group' => 'Master Data', 'roles' => ['super_admin']],
        ['key' => 'village_assets.view', 'label' => 'View village assets', 'group' => 'Village Assets', 'roles' => ['super_admin', 'state_admin', 'district_admin', 'block_admin', 'department_head', 'department_officer', 'engineer', 'sarpanch', 'secretary']],
        ['key' => 'village_assets.manage', 'label' => 'Create/edit/delete village assets', 'group' => 'Village Assets', 'roles' => ['super_admin', 'block_admin', 'department_officer', 'engineer', 'sarpanch', 'secretary']],
    ];

    public function run(): void
    {
        foreach (self::PERMISSIONS as $def) {
            $permission = Permission::firstOrCreate(
                ['key' => $def['key']],
                ['label' => $def['label'], 'group' => $def['group']]
            );

            foreach ($def['roles'] as $role) {
                RolePermission::firstOrCreate(['role' => $role, 'permission_id' => $permission->id]);
            }
        }
    }
}
