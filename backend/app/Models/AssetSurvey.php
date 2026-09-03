<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'asset_code', 'surveyor_id', 'panchayat_id', 'block_id', 'district_id', 'department_id', 'asset_type_id', 'asset_name',
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

    public function panchayat(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class);
    }

    public function assetType(): BelongsTo
    {
        return $this->belongsTo(AssetType::class);
    }

    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by_id');
    }

    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function reviews(): HasMany
    {
        return $this->hasMany(AssetSurveyReview::class, 'survey_id');
    }
}
