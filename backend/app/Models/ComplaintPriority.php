<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['name', 'level', 'is_active'])]
class ComplaintPriority extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }
}
