<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'user_id', 'full_name', 'mobile', 'email', 'registration_source',
    'registered_at', 'last_login_at',
])]
class CitizenProfile extends Model
{
    protected function casts(): array
    {
        return [
            'registered_at' => 'datetime',
            'last_login_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
