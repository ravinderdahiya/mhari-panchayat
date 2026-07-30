<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['key', 'label', 'group'])]
class Permission extends Model
{
    public function rolePermissions(): HasMany
    {
        return $this->hasMany(RolePermission::class);
    }
}
