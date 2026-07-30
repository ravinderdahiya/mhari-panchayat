<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'district_id'])]
class Block extends Model
{
    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function panchayats(): HasMany
    {
        return $this->hasMany(Panchayat::class);
    }
}
