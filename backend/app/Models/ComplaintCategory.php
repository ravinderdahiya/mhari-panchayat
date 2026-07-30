<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'sort_order', 'parent_id', 'district_id'])]
class ComplaintCategory extends Model
{
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
}
