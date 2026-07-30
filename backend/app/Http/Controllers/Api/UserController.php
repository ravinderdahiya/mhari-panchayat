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
        $users = User::with('department')->orderByDesc('created_at')->get();

        return response()->json(['success' => true, 'users' => $users]);
    }

    // Lightweight, non-admin-gated user list for "assign/transfer to" pickers -
    // just enough to label a dropdown, not the full user-management payload
    // that /users (super_admin only) returns.
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
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $isSelf = $request->user()->id === $user->id;
        $demotesSelf = $isSelf && array_key_exists('role', $data) && $data['role'] !== 'super_admin';
        $deactivatesSelf = $isSelf && array_key_exists('is_active', $data) && ! $data['is_active'];

        if ($demotesSelf || $deactivatesSelf) {
            return response()->json(['success' => false, 'message' => 'You cannot change your own role or deactivate your own account'], 400);
        }

        $user->update($data);

        return response()->json(['success' => true, 'message' => 'User updated successfully', 'user' => $user->fresh('department')]);
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
