<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'short_code', 'state_id', 'is_active'])]
class District extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function state(): BelongsTo
    {
        return $this->belongsTo(State::class);
    }

    public function blocks(): HasMany
    {
        return $this->hasMany(Block::class);
    }

    public function tehsils(): HasMany
    {
        return $this->hasMany(Tehsil::class);
    }
}
