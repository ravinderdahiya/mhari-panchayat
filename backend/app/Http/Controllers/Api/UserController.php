<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Panchayat;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UserController extends Controller
{
    public function index(Request $request)
    {
        $data = $request->validate([
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            // Comma-separated to support multi-role tabs (e.g. the CPLO
            // management screen's "Surveyor (CPLO)" tab covers both the
            // imported `cplo` role and `surveyor`s acting as CPLO).
            'role' => ['sometimes', 'nullable', 'string'],
            'district_id' => ['sometimes', 'nullable', 'integer'],
            'block_id' => ['sometimes', 'nullable', 'integer'],
            'panchayat_id' => ['sometimes', 'nullable', 'integer'],
            'status' => ['sometimes', 'string', 'in:all,active,inactive'],
        ]);

        $query = User::with(['department', 'departments', 'district', 'block:id,name', 'panchayat:id,name', 'villages'])
            ->where('role', '!=', 'citizen');

        $search = trim((string) ($data['q'] ?? ''));
        if ($search !== '') {
            $needle = '%'.mb_strtolower($search).'%';
            $query->where(function ($userQuery) use ($needle) {
                $userQuery
                    ->whereRaw('LOWER(username) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(name) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(email) LIKE ?', [$needle]);
            });
        }

        if (! empty($data['role'])) {
            $roles = array_values(array_filter(array_map('trim', explode(',', $data['role']))));
            $query->whereIn('role', $roles);
        }

        if (! empty($data['district_id'])) {
            $query->where('district_id', $data['district_id']);
        }

        if (! empty($data['block_id'])) {
            $query->where(function ($blockQuery) use ($data) {
                $blockQuery
                    ->where('block_id', $data['block_id'])
                    ->orWhereHas('blocks', fn ($assigned) => $assigned->where('blocks.id', $data['block_id']));
            });
        }

        if (! empty($data['panchayat_id'])) {
            $query->where('panchayat_id', $data['panchayat_id']);
        }

        $status = $data['status'] ?? 'all';
        if ($status !== 'all') {
            $query->where('is_active', $status === 'active');
        }

        $query->orderByDesc('created_at');

        // Only paginate when the caller opts in (page present) - some callers
        // (e.g. the surveyor management screen) still need the full list.
        if ($request->has('page')) {
            $paginator = $query->paginate((int) ($data['per_page'] ?? 10));
            $this->backfillEmployeeIds($paginator->getCollection());
            $this->revealLoginPasswords($paginator->getCollection());

            return response()->json([
                'success' => true,
                'users' => $paginator->getCollection()->values(),
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

        $users = $query->get();
        $this->backfillEmployeeIds($users);
        $this->revealLoginPasswords($users);

        return response()->json(['success' => true, 'users' => $users->values()]);
    }

    // Ensure every surveyor has an emp code (safety net after migration).
    private function backfillEmployeeIds($users): void
    {
        foreach ($users as $user) {
            if ($user->role !== 'surveyor' || filled($user->employee_id)) {
                continue;
            }
            $distCode = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) ($user->district?->code ?: 'GEN')) ?: 'GEN');
            $user->forceFill([
                'employee_id' => sprintf('SUR-%s-%04d', $distCode, $user->id),
            ])->save();
        }
    }

    private function revealLoginPasswords($users): void
    {
        foreach ($users as $user) {
            $user->appendRevealedLoginPassword();
        }
    }

    public function assignable(Request $request)
    {
        if ($request->user()->role === 'citizen') {
            return response()->json(['success' => false, 'message' => 'Not authorized'], 403);
        }

        $users = User::where('is_active', true)
            ->where('role', '!=', 'citizen')
            ->with(['district:id,name', 'block:id,name', 'panchayat:id,name'])
            ->orderBy('name')
            ->get(['id', 'name', 'username', 'role', 'district_id', 'block_id', 'panchayat_id']);

        return response()->json(['success' => true, 'users' => $users]);
    }

    public function update(Request $request, int $id)
    {
        $user = User::findOrFail($id);

        $data = $request->validate([
            'name' => ['sometimes', 'nullable', 'string', 'max:150'],
            'mobile' => ['sometimes', 'nullable', 'string', 'max:20'],
            'email' => ['sometimes', 'nullable', 'email', 'max:150'],
            'employee_id' => ['sometimes', 'nullable', 'string', 'max:50'],
            'member_id' => ['sometimes', 'nullable', 'string', 'max:50'],
            'family_id' => ['sometimes', 'nullable', 'string', 'max:50'],
            'role' => ['sometimes', 'string', Rule::exists('roles', 'name')],
            'department_id' => ['sometimes', 'nullable', 'exists:departments,id'],
            'department_ids' => ['sometimes', 'array'],
            'department_ids.*' => ['integer', 'exists:departments,id'],
            'district_id' => ['sometimes', 'nullable', 'exists:districts,id'],
            'block_id' => ['sometimes', 'nullable', 'exists:blocks,id'],
            'panchayat_id' => ['sometimes', 'nullable', 'exists:panchayats,id'],
            'village_ids' => ['sometimes', 'array'],
            'village_ids.*' => ['integer', 'exists:villages,id'],
            'is_active' => ['sometimes', 'boolean'],
            'password' => ['sometimes', 'nullable', 'string', 'min:8'],
        ]);

        // Setting a panchayat also fixes up block/district so the three stay
        // consistent (mirrors ImportHaryanaOfficials' CPLO jurisdiction wiring)
        // - used by the CPLO / Gram Sachiv panchayat-assignment screen. This
        // runs after the plain `block_id`/`district_id` validation above so a
        // panchayat pick always wins over a stale block/district selection
        // made before it (e.g. BDPO/DDPO edits set block/district directly,
        // with no panchayat involved at all).
        if (array_key_exists('panchayat_id', $data)) {
            $panchayat = $data['panchayat_id'] ? Panchayat::with('block')->find($data['panchayat_id']) : null;
            $data['block_id'] = $panchayat?->block_id;
            $data['district_id'] = $panchayat?->block?->district_id;
        }

        $isSelf = $request->user()->id === $user->id;
        $demotesSelf = $isSelf && array_key_exists('role', $data) && $data['role'] !== $user->role && $user->isSuperAdmin();
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

        if (! filled($data['password'] ?? null)) {
            unset($data['password']);
        }

        if ($villageIds !== null) {
            $user->villages()->sync($villageIds);
        }

        if ($data !== []) {
            $user->update($data);
        }

        return response()->json([
            'success' => true,
            'message' => 'User updated successfully',
            'user' => $user->fresh(['department', 'departments', 'district', 'block:id,name', 'panchayat:id,name', 'villages'])
                ?->appendRevealedLoginPassword(),
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
