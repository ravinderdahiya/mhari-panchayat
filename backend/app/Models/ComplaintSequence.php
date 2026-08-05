<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['district_id', 'year', 'month', 'last_number'])]
class ComplaintSequence extends Model
{
}
