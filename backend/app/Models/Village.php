<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['name', 'code', 'panchayat_id', 'tehsil_id', 'is_active'])]
class Village extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function panchayat(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class);
    }

    public function tehsil(): BelongsTo
    {
        return $this->belongsTo(Tehsil::class);
    }
}
