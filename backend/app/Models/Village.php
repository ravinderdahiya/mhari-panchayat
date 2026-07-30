<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['name', 'code', 'panchayat_id'])]
class Village extends Model
{
    public function panchayat(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class);
    }
}
