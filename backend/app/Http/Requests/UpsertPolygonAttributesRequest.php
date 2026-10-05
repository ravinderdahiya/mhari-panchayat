<?php

namespace App\Http\Requests;

use App\Models\SurveyPolygonAttribute;

class UpsertPolygonAttributesRequest extends ApiFormRequest
{
    public function rules(): array
    {
        return SurveyPolygonAttribute::rules();
    }
}
