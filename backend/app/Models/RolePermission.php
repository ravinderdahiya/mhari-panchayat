<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['role', 'permission_id'])]
class RolePermission extends Model
{
    public function permission(): BelongsTo
    {
        return $this->belongsTo(Permission::class);
    }
}
