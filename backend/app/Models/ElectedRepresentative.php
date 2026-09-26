<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'tier', 'district_id', 'block_id', 'panchayat_id', 'ward_no',
    'name', 'father_name', 'mobile', 'gender', 'source_sr_no',
])]
class ElectedRepresentative extends Model
{
    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }

    public function panchayat(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class);
    }
}
