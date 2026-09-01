<?php

use App\Enums\Role as RoleEnum;
use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        $now = now();
        $details = Role::CATALOG['super_admin'];

        if (! DB::table('roles')->where('name', 'super_admin')->exists()) {
            DB::table('roles')->insert([
                'name' => 'super_admin',
                'full_name' => $details['full_name'],
                'main_responsibility' => $details['main_responsibility'],
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            DB::table('roles')->where('name', 'super_admin')->update($details);
        }

        DB::table('users')->where('role', 'admin')->update(['role' => 'super_admin']);

        $newPermissions = [
            ['key' => 'users.manage', 'label' => 'Manage users', 'group' => 'Administration'],
            ['key' => 'roles.manage', 'label' => 'Manage roles & permissions', 'group' => 'Administration'],
            ['key' => 'settings.manage', 'label' => 'System configuration & security settings', 'group' => 'Administration'],
            ['key' => 'audit.view', 'label' => 'View audit logs', 'group' => 'Administration'],
            ['key' => 'workflow.manage', 'label' => 'Configure workflows', 'group' => 'Administration'],
            ['key' => 'reports.view', 'label' => 'View system reports', 'group' => 'Reports'],
        ];

        foreach ($newPermissions as $permission) {
            $existing = DB::table('permissions')->where('key', $permission['key'])->first();
            if ($existing) {
                continue;
            }
            DB::table('permissions')->insert([
                ...$permission,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $permissionIds = DB::table('permissions')->pluck('id');
        foreach ($permissionIds as $permissionId) {
            $exists = DB::table('role_permissions')
                ->where('role', RoleEnum::SuperAdmin->value)
                ->where('permission_id', $permissionId)
                ->exists();
            if ($exists) {
                continue;
            }
            DB::table('role_permissions')->insert([
                'role' => RoleEnum::SuperAdmin->value,
                'permission_id' => $permissionId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    public function down(): void
    {
        DB::table('users')->where('role', 'super_admin')->update(['role' => 'admin']);
        DB::table('role_permissions')->where('role', 'super_admin')->delete();
        DB::table('roles')->where('name', 'super_admin')->delete();
    }
};
