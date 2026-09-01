<?php

namespace App\Http\Middleware;

use App\Models\Role;
use Closure;
use Illuminate\Http\Request;

class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles)
    {
        $role = $request->user()?->role;
        if (Role::isSuperAdmin($role) || in_array($role, $roles, true)) {
            return $next($request);
        }

        return response()->json(['success' => false, 'message' => 'You do not have permission to perform this action'], 403);
    }
}
