<?php

namespace App\Http\Middleware;

use App\Models\Role;
use App\Models\RolePermission;
use Closure;
use Illuminate\Http\Request;

class EnsurePermission
{
    public function handle(Request $request, Closure $next, string $permissionKey)
    {
        $role = $request->user()?->role;

        if (Role::isSuperAdmin($role)) {
            return $next($request);
        }

        $granted = $role && RolePermission::whereHas('permission', fn ($q) => $q->where('key', $permissionKey))
            ->where('role', $role)
            ->exists();

        if (! $granted) {
            return response()->json(['success' => false, 'message' => 'You do not have permission to perform this action'], 403);
        }

        return $next($request);
    }
}
