<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'asset_code', 'surveyor_id', 'department_id', 'asset_type_id', 'asset_name',
    'district', 'panchayat', 'village', 'latitude', 'longitude', 'condition',
    'description', 'survey_date', 'photo_paths',
    'review_status', 'reviewed_by_id', 'reviewed_at', 'rejection_reason',
])]
class AssetSurvey extends Model
{
    protected function casts(): array
    {
        return [
            'latitude' => 'float',
            'longitude' => 'float',
            'survey_date' => 'datetime',
            'photo_paths' => 'array',
            'reviewed_at' => 'datetime',
        ];
    }

    public function surveyor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'surveyor_id');
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function assetType(): BelongsTo
    {
        return $this->belongsTo(AssetType::class);
    }

    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by_id');
    }
}
