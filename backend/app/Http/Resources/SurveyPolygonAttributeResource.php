<?php

namespace App\Http\Resources;

use App\Models\SurveyPolygonAttribute;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\SurveyPolygonAttribute */
class SurveyPolygonAttributeResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $out = [];
        foreach (SurveyPolygonAttribute::fixedFields() as $field) {
            $out[$field] = $this->{$field};
        }
        $out['extra'] = $this->extra ?? (object) [];
        $out['updated_at'] = $this->updated_at?->toIso8601String();

        return $out;
    }
}
