<?php

namespace App\Http\Resources;

use App\Models\SurveyPolygonAttribute;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

// One polygon as a GeoJSON Feature: geometry = polygon, properties = polygon
// stats merged with its attribute row (and the raw track when selected).
// Expects the model loaded with SurveyPolygon::withGeoJson() + with('attribute').
/** @mixin \App\Models\SurveyPolygon */
class SurveyPolygonFeatureResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $properties = [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'description' => $this->description,
            'area_sqm' => $this->area_sqm,
            'perimeter_m' => $this->perimeter_m,
            'point_count' => $this->point_count,
            'started_at' => $this->started_at?->toIso8601String(),
            'ended_at' => $this->ended_at?->toIso8601String(),
            'source' => $this->source,
            'created_at' => $this->created_at?->toIso8601String(),
            'has_data' => false,
        ];

        $attr = $this->relationLoaded('attribute') ? $this->attribute : null;
        foreach (SurveyPolygonAttribute::fixedFields() as $field) {
            $properties[$field] = $attr?->{$field};
        }
        if ($attr) {
            $properties['has_data'] = true;
            $properties['extra'] = $attr->extra ?? (object) [];
        }

        if (array_key_exists('track_geojson', $this->resource->getAttributes())) {
            $properties['track'] = $this->track_geojson ? json_decode($this->track_geojson, true) : null;
        }

        return [
            'type' => 'Feature',
            'id' => $this->uuid,
            'geometry' => json_decode($this->geom_geojson, true),
            'properties' => $properties,
        ];
    }
}
