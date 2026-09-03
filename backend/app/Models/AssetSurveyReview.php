<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['survey_id', 'actor_id', 'actor_role', 'action', 'remarks'])]
class AssetSurveyReview extends Model
{
    public function survey(): BelongsTo
    {
        return $this->belongsTo(AssetSurvey::class, 'survey_id');
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}
