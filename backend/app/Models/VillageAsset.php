<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'village_id', 'category', 'subtype', 'asset_name', 'geometry_type',
    'latitude', 'longitude', 'path', 'status', 'condition', 'ward_no',
    'installed_date', 'last_inspected', 'remarks', 'photo_url', 'created_by',
])]
class VillageAsset extends Model
{
    protected $casts = [
        'path' => 'array',
        'latitude' => 'float',
        'longitude' => 'float',
    ];

    public function village(): BelongsTo
    {
        return $this->belongsTo(Village::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
