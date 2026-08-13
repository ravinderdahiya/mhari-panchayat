<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;

class UserController extends Controller
{
    private const ALL_ROLES = [
        'super_admin', 'state_admin', 'district_admin', 'block_admin', 'department_head',
        'department_officer', 'engineer', 'sarpanch', 'secretary', 'citizen', 'contractor', 'vendor',
    ];

    public function index()
    {
        $users = User::with(['department', 'departments', 'district', 'villages'])
            ->where('role', '!=', 'citizen')
            ->orderByDesc('created_at')
            ->get();

        // Ensure every surveyor has an emp code (safety net after migration).
        foreach ($users as $user) {
            if ($user->role !== 'engineer' || filled($user->employee_id)) {
                continue;
            }
            $distCode = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) ($user->district?->code ?: 'GEN')) ?: 'GEN');
            $user->forceFill([
                'employee_id' => sprintf('SUR-%s-%04d', $distCode, $user->id),
            ])->save();
        }

        return response()->json(['success' => true, 'users' => $users->values()]);
    }

    public function assignable(Request $request)
    {
        if ($request->user()->role === 'citizen') {
            return response()->json(['success' => false, 'message' => 'Not authorized'], 403);
        }

        $users = User::where('is_active', true)
            ->where('role', '!=', 'citizen')
            ->orderBy('name')
            ->get(['id', 'name', 'username', 'role']);

        return response()->json(['success' => true, 'users' => $users]);
    }

    public function update(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        $data = $request->validate([
            'role' => ['sometimes', 'string', 'in:'.implode(',', self::ALL_ROLES)],
            'department_id' => ['sometimes', 'nullable', 'exists:departments,id'],
            'department_ids' => ['sometimes', 'array'],
            'department_ids.*' => ['integer', 'exists:departments,id'],
            'district_id' => ['sometimes', 'nullable', 'exists:districts,id'],
            'village_ids' => ['sometimes', 'array'],
            'village_ids.*' => ['integer', 'exists:villages,id'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $isSelf = $request->user()->id === $user->id;
        $demotesSelf = $isSelf && array_key_exists('role', $data) && $data['role'] !== 'super_admin';
        $deactivatesSelf = $isSelf && array_key_exists('is_active', $data) && ! $data['is_active'];

        if ($demotesSelf || $deactivatesSelf) {
            return response()->json(['success' => false, 'message' => 'You cannot change your own role or deactivate your own account'], 400);
        }

        $departmentIds = $data['department_ids'] ?? null;
        unset($data['department_ids']);

        if ($departmentIds !== null) {
            $user->departments()->sync($departmentIds);
            // Keep legacy single department_id in sync with the first assigned dept.
            $data['department_id'] = $departmentIds[0] ?? null;
        }

        $villageIds = $data['village_ids'] ?? null;
        unset($data['village_ids']);

        if ($villageIds !== null) {
            $user->villages()->sync($villageIds);
        }

        if ($data !== []) {
            $user->update($data);
        }

        return response()->json([
            'success' => true,
            'message' => 'User updated successfully',
            'user' => $user->fresh(['department', 'departments', 'district', 'villages']),
        ]);
    }

    public function destroy(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        if ($request->user()->id === $user->id) {
            return response()->json(['success' => false, 'message' => 'You cannot delete your own account'], 400);
        }

        $user->delete();

        return response()->json(['success' => true, 'message' => 'User deleted successfully']);
    }
}
