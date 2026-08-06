<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'name', 'name_hi', 'code', 'sort_order', 'parent_id', 'district_id',
    'department_id', 'asset_type_id', 'default_priority_id', 'is_active',
])]
class ComplaintCategory extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(ComplaintCategory::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(ComplaintCategory::class, 'parent_id');
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function assetType(): BelongsTo
    {
        return $this->belongsTo(AssetType::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function defaultPriority(): BelongsTo
    {
        return $this->belongsTo(ComplaintPriority::class, 'default_priority_id');
    }
}
