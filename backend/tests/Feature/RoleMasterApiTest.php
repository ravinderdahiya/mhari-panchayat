<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Database\Seeders\PermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RoleMasterApiTest extends TestCase
{
    use RefreshDatabase;

    private function actingAdmin()
    {
        $this->seed(PermissionSeeder::class);

        return $this->actingAs(User::factory()->create(['role' => 'super_admin']), 'sanctum');
    }

    public function test_admin_can_crud_roles_and_cannot_delete_admin_or_assigned_roles(): void
    {
        $this->actingAdmin();

        $this->getJson('/api/master/roles?paginated=1')
            ->assertOk()
            ->assertJsonPath('success', true);

        $created = $this->postJson('/api/master/roles', [
            'name' => 'Block Officer',
            'is_active' => true,
        ])->assertCreated()->json('item');

        $this->assertSame('block_officer', $created['name']);
        $this->assertTrue($created['is_active']);
        $this->assertDatabaseHas('roles', ['name' => 'block_officer']);

        $this->putJson('/api/master/roles/'.$created['id'], [
            'name' => 'block_officer',
            'is_active' => false,
        ])->assertOk()->assertJsonPath('item.is_active', false);

        $adminRole = Role::where('is_super_admin', true)->firstOrFail();
        $this->deleteJson('/api/master/roles/'.$adminRole->id)
            ->assertStatus(400)
            ->assertJsonPath('message', 'The Super Admin role cannot be deleted');

        $assigned = Role::create(['name' => 'temp_role', 'is_active' => true]);
        User::factory()->create(['role' => 'temp_role']);
        $this->deleteJson('/api/master/roles/'.$assigned->id)
            ->assertStatus(400);

        $this->deleteJson('/api/master/roles/'.$created['id'])->assertOk();
        $this->assertDatabaseMissing('roles', ['id' => $created['id']]);
    }

    public function test_permissions_matrix_and_user_role_use_the_roles_table(): void
    {
        $this->actingAdmin();

        Role::create(['name' => 'field_inspector', 'is_active' => true]);

        $this->getJson('/api/roles/permissions')
            ->assertOk()
            ->assertJsonFragment(['field_inspector']);

        $view = Permission::where('key', 'complaints.view')->firstOrFail();
        $this->putJson('/api/roles/field_inspector/permissions', [
            'permissions' => ['complaints.view'],
        ])->assertOk();

        $this->assertDatabaseHas('role_permissions', [
            'role' => 'field_inspector',
            'permission_id' => $view->id,
        ]);

        $user = User::factory()->create(['role' => 'surveyor']);
        $this->patchJson('/api/users/'.$user->id, ['role' => 'field_inspector'])
            ->assertOk()
            ->assertJsonPath('user.role', 'field_inspector');
    }
}
