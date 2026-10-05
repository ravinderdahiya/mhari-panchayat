<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

// Geometry side of a surveyed boundary: a closed Polygon (geom) plus the raw
// walked LineString (track). Attribute data lives in SurveyPolygonAttribute.
// Geometry columns are never selected as-is (they'd come back as hex EWKB) -
// use the scopes below to pull them as GeoJSON.
class SurveyPolygon extends Model
{
    use SoftDeletes;

    public const SOURCE_ONLINE = 'online';
    public const SOURCE_OFFLINE_SYNC = 'offline_sync';
    public const SOURCE_SHP_IMPORT = 'shp_import';

    protected $fillable = [
        'uuid', 'user_id', 'description', 'raw_points', 'area_sqm', 'perimeter_m',
        'point_count', 'started_at', 'ended_at', 'source',
    ];

    protected $casts = [
        'raw_points' => 'array',
        'area_sqm' => 'float',
        'perimeter_m' => 'float',
        'point_count' => 'integer',
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
    ];

    private const SCALAR_COLUMNS = [
        'survey_polygons.id', 'survey_polygons.uuid', 'survey_polygons.user_id', 'survey_polygons.description',
        'survey_polygons.area_sqm', 'survey_polygons.perimeter_m', 'survey_polygons.point_count',
        'survey_polygons.started_at', 'survey_polygons.ended_at', 'survey_polygons.source',
        'survey_polygons.created_at', 'survey_polygons.updated_at', 'survey_polygons.deleted_at',
    ];

    public function attribute(): HasOne
    {
        return $this->hasOne(SurveyPolygonAttribute::class, 'polygon_id');
    }

    /** Scalar columns only - for list endpoints. */
    public function scopeSummary(Builder $query): void
    {
        $query->select(self::SCALAR_COLUMNS);
    }

    /** Scalar columns plus geom (and optionally track) as GeoJSON strings. */
    public function scopeWithGeoJson(Builder $query, bool $includeTrack = true): void
    {
        $query->select(self::SCALAR_COLUMNS)->selectRaw('ST_AsGeoJSON(survey_polygons.geom) AS geom_geojson');

        if ($includeTrack) {
            $query->selectRaw('ST_AsGeoJSON(survey_polygons.track) AS track_geojson');
        }
    }

    /** Polygons intersecting the bounding box (all bound params). */
    public function scopeIntersectsBbox(Builder $query, float $minLng, float $minLat, float $maxLng, float $maxLat): void
    {
        $query->whereRaw(
            'ST_Intersects(survey_polygons.geom, ST_MakeEnvelope(?, ?, ?, ?, 4326))',
            [$minLng, $minLat, $maxLng, $maxLat],
        );
    }
}
