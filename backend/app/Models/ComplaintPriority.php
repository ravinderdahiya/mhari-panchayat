<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['name', 'level', 'is_active', 'sla_hours'])]
class ComplaintPriority extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean', 'sla_hours' => 'integer'];
    }
}
