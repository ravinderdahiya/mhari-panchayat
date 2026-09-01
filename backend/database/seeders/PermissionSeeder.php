<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\Permission;
use App\Models\Role as RoleRecord;
use App\Models\RolePermission;
use Illuminate\Database\Seeder;

// Seeds the exact permission matrix that already existed as hardcoded role
// lists in routes/api.php - flipping the gates from role: to permission:
// changes nothing on day one, it's purely additive until an admin edits a
// checkbox on the Roles page.
class PermissionSeeder extends Seeder
{
    /** @return list<array{key: string, label: string, group: string, roles: list<string>}> */
    private static function permissions(): array
    {
        $allRoles = Role::values();
        $superAdmins = RoleRecord::superAdminNames();

        return [
            ['key' => 'complaints.file', 'label' => 'File complaints', 'group' => 'Complaints', 'roles' => $allRoles],
            ['key' => 'complaints.view', 'label' => 'View complaints', 'group' => 'Complaints', 'roles' => $allRoles],
            ['key' => 'complaints.view_reports', 'label' => 'View dashboard reports', 'group' => 'Complaints', 'roles' => $allRoles],
            ['key' => 'complaints.acknowledge', 'label' => 'Acknowledge complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'bdpo', 'ddpo', 'deputy_commissioner']],
            ['key' => 'complaints.survey', 'label' => 'Submit field survey', 'group' => 'Complaints', 'roles' => ['surveyor']],
            ['key' => 'complaints.resolve', 'label' => 'Resolve complaints', 'group' => 'Complaints', 'roles' => ['department_officer', 'department_head', 'admin', 'ddpo', 'deputy_commissioner']],
            ['key' => 'complaints.verify', 'label' => 'Verify field reports', 'group' => 'Complaints', 'roles' => ['department_officer', 'department_head', 'admin']],
            ['key' => 'complaints.rate', 'label' => 'Rate & close complaints', 'group' => 'Complaints', 'roles' => ['citizen']],
            ['key' => 'complaints.transfer', 'label' => 'Transfer complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'bdpo', 'department_head', 'department_officer', 'admin', 'ddpo', 'deputy_commissioner']],
            ['key' => 'complaints.reopen', 'label' => 'Reopen complaints', 'group' => 'Complaints', 'roles' => ['citizen']],
            ['key' => 'complaints.reject', 'label' => 'Reject complaints', 'group' => 'Complaints', 'roles' => ['sarpanch', 'secretary', 'bdpo', 'department_head', 'department_officer', 'admin', 'ddpo', 'deputy_commissioner']],
            ['key' => 'master_data.view', 'label' => 'View master data', 'group' => 'Master Data', 'roles' => $allRoles],
            ['key' => 'master_data.manage', 'label' => 'Create/edit/delete master data', 'group' => 'Master Data', 'roles' => ['admin']],
            ['key' => 'village_assets.view', 'label' => 'View village assets', 'group' => 'Village Assets', 'roles' => ['admin', 'state_admin', 'ddpo', 'bdpo', 'department_head', 'department_officer', 'surveyor', 'xen_pr', 'sarpanch', 'secretary']],
            ['key' => 'village_assets.manage', 'label' => 'Create/edit/delete village assets', 'group' => 'Village Assets', 'roles' => ['admin', 'bdpo', 'department_officer', 'surveyor', 'xen_pr', 'sarpanch', 'secretary']],
            ['key' => 'users.manage', 'label' => 'Manage users', 'group' => 'Administration', 'roles' => $superAdmins],
            ['key' => 'roles.manage', 'label' => 'Manage roles & permissions', 'group' => 'Administration', 'roles' => $superAdmins],
            ['key' => 'settings.manage', 'label' => 'System configuration & security settings', 'group' => 'Administration', 'roles' => $superAdmins],
            ['key' => 'audit.view', 'label' => 'View audit logs', 'group' => 'Administration', 'roles' => $superAdmins],
            ['key' => 'workflow.manage', 'label' => 'Configure workflows', 'group' => 'Administration', 'roles' => $superAdmins],
            ['key' => 'reports.view', 'label' => 'View system reports', 'group' => 'Reports', 'roles' => $superAdmins],
        ];
    }

    public function run(): void
    {
        foreach (self::permissions() as $def) {
            $permission = Permission::firstOrCreate(
                ['key' => $def['key']],
                ['label' => $def['label'], 'group' => $def['group']]
            );

            foreach ($def['roles'] as $role) {
                RolePermission::firstOrCreate(['role' => $role, 'permission_id' => $permission->id]);
            }
        }

        foreach (RoleRecord::superAdminNames() as $role) {
            foreach (Permission::pluck('id') as $permissionId) {
                RolePermission::firstOrCreate([
                    'role' => $role,
                    'permission_id' => $permissionId,
                ]);
            }
        }
    }
}
