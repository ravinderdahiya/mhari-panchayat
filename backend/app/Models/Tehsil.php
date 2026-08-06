<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'district_id', 'is_active'])]
class Tehsil extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function villages(): HasMany
    {
        return $this->hasMany(Village::class);
    }
}
