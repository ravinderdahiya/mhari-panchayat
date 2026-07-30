<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'block_id'])]
class Panchayat extends Model
{
    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }

    public function villages(): HasMany
    {
        return $this->hasMany(Village::class);
    }
}
