<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\SurveyPolygon */
class SurveyPolygonSummaryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $attr = $this->relationLoaded('attribute') ? $this->attribute : null;

        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'area_sqm' => $this->area_sqm,
            'perimeter_m' => $this->perimeter_m,
            'point_count' => $this->point_count,
            'started_at' => $this->started_at?->toIso8601String(),
            'source' => $this->source,
            'has_data' => $attr !== null,
            'owner_name' => $attr?->owner_name,
            'village' => $attr?->village,
            'khasra_no' => $attr?->khasra_no,
        ];
    }
}
