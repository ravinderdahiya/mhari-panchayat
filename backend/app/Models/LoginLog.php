<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class LoginLog extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = [
        'user_id', 'identifier', 'role', 'method', 'status', 'reason', 'ip_address', 'user_agent',
        'latitude', 'longitude',
    ];

    protected function casts(): array
    {
        return ['latitude' => 'float', 'longitude' => 'float'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Record a sign-in attempt. Never throws: a logging problem must not stop anyone signing in.
     */
    public static function record(
        Request $request,
        string $method,
        string $status,
        ?string $identifier,
        ?User $user = null,
        ?string $reason = null,
    ): void {
        try {
            static::create([
                'user_id' => $user?->id,
                'identifier' => $identifier !== null ? Str::limit($identifier, 188, '') : null,
                'role' => $user?->role,
                'method' => $method,
                'status' => $status,
                'reason' => $reason !== null ? Str::limit($reason, 250) : null,
                'ip_address' => $request->ip(),
                'latitude' => $request->input('latitude'),
                'longitude' => $request->input('longitude'),
                'user_agent' => Str::limit((string) $request->userAgent(), 497) ?: null,
            ]);
        } catch (\Throwable $e) {
            Log::warning('Could not write login log', ['error' => $e->getMessage()]);
        }
    }
}
