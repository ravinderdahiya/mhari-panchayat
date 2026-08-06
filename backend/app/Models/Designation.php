<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['name', 'is_active'])]
class Designation extends Model
{
    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }
}
