<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'icon_key', 'sort_order', 'is_active'])]
class AssetType extends Model
{
    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function departments(): BelongsToMany
    {
        return $this->belongsToMany(Department::class)->withTimestamps();
    }

    public function surveys(): HasMany
    {
        return $this->hasMany(AssetSurvey::class);
    }
}
