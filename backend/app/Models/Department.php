<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code'])]
class Department extends Model
{
    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class)->withTimestamps();
    }

    public function assetTypes(): BelongsToMany
    {
        return $this->belongsToMany(AssetType::class)->withTimestamps();
    }

    public function assetSurveys(): HasMany
    {
        return $this->hasMany(AssetSurvey::class);
    }
}
