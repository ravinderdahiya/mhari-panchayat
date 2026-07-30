<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles)
    {
        if (! in_array($request->user()?->role, $roles, true)) {
            return response()->json(['success' => false, 'message' => 'You do not have permission to perform this action'], 403);
        }

        return $next($request);
    }
}
