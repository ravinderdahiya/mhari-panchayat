<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\LoginLog;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

// Admin "Audit Log" page: sign-in history (staff password + citizen OTP).
// Guarded by permission:audit.view (super admins by default - see PermissionSeeder).
class LoginLogController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $filters = $request->validate([
            'status' => ['nullable', 'in:success,failed'],
            'method' => ['nullable', 'in:password,otp'],
            'search' => ['nullable', 'string', 'max:100'],
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:10,200'],
        ]);

        // Shared filters except status, so the summary counts follow search/date/method.
        $base = LoginLog::query()
            ->when($filters['method'] ?? null, fn (Builder $q, $m) => $q->where('method', $m))
            ->when($filters['from'] ?? null, fn (Builder $q, $d) => $q->where('created_at', '>=', $d.' 00:00:00'))
            ->when($filters['to'] ?? null, fn (Builder $q, $d) => $q->where('created_at', '<=', $d.' 23:59:59'))
            ->when($filters['search'] ?? null, function (Builder $q, string $term) {
                $like = '%'.mb_strtolower($term).'%';
                $q->where(function (Builder $w) use ($like) {
                    $w->whereRaw('LOWER(identifier) LIKE ?', [$like])
                        ->orWhereRaw('LOWER(ip_address) LIKE ?', [$like])
                        ->orWhereHas('user', fn (Builder $u) => $u
                            ->whereRaw('LOWER(name) LIKE ?', [$like])
                            ->orWhereRaw('LOWER(username) LIKE ?', [$like]));
                });
            });

        $summary = (clone $base)
            ->selectRaw('status, COUNT(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status');

        $page = (clone $base)
            ->when($filters['status'] ?? null, fn (Builder $q, $s) => $q->where('status', $s))
            ->with('user:id,name,username')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($filters['per_page'] ?? 50);

        return response()->json([
            'success' => true,
            'logs' => collect($page->items())->map(fn (LoginLog $log) => [
                'id' => $log->id,
                'userId' => $log->user_id,
                'userName' => $log->user?->name ?: $log->user?->username,
                'identifier' => $log->identifier,
                'role' => $log->role,
                'method' => $log->method,
                'status' => $log->status,
                'reason' => $log->reason,
                'ipAddress' => $log->ip_address,
                'latitude' => $log->latitude,
                'longitude' => $log->longitude,
                'userAgent' => $log->user_agent,
                'createdAt' => $log->created_at?->toISOString(),
            ])->values(),
            'summary' => [
                'success' => (int) ($summary['success'] ?? 0),
                'failed' => (int) ($summary['failed'] ?? 0),
            ],
            'meta' => [
                'total' => $page->total(),
                'page' => $page->currentPage(),
                'lastPage' => $page->lastPage(),
                'perPage' => $page->perPage(),
            ],
        ]);
    }
}
