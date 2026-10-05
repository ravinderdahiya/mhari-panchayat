<?php

namespace App\Services;

use App\Exceptions\PolygonException;
use App\Models\SurveyPolygon;
use App\Models\SurveyPolygonAttribute;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

// Turns a recorded GPS track into a PostGIS Polygon (+ the raw LineString).
// All geometry is built inside Postgres from a bound JSON parameter - no
// coordinate is ever concatenated into SQL.
class TrackedPolygonService
{
    /**
     * Idempotent create keyed on (user, uuid).
     *
     * @param  array<string, mixed>  $data  validated payload (see StorePolygonRequest)
     * @return array{0: SurveyPolygon, 1: bool}  [record, wasCreated]
     */
    public function store(User $user, array $data): array
    {
        // withTrashed: a uuid the server has already seen counts as a duplicate
        // even if the user deleted it, so a stale offline queue can't resurrect it.
        $existing = $this->findForUser($user, $data['uuid']);
        if ($existing) {
            return [$existing, false];
        }

        $points = $this->cleanPoints($data['points']);

        try {
            $id = DB::transaction(function () use ($user, $data, $points) {
                $id = $this->insert($user, $data, $points);
                if (! empty($data['attributes'])) {
                    SurveyPolygonAttribute::upsertFor($id, $data['attributes']);
                }

                return $id;
            });
        } catch (UniqueConstraintViolationException) {
            // Lost a race with a concurrent request carrying the same uuid.
            $existing = $this->findForUser($user, $data['uuid']);
            if ($existing) {
                return [$existing, false];
            }

            throw new PolygonException('This uuid is already in use.', ['uuid' => ['This uuid is already in use.']], 409);
        }

        return [SurveyPolygon::withGeoJson()->with('attribute')->findOrFail($id), true];
    }

    public function findForUser(User $user, string $uuid): ?SurveyPolygon
    {
        return SurveyPolygon::withTrashed()
            ->withGeoJson()
            ->with('attribute')
            ->where('user_id', $user->id)
            ->where('uuid', $uuid)
            ->first();
    }

    /**
     * Drop low-accuracy fixes and consecutive duplicates; keep recorded order.
     *
     * @param  array<int, array<string, mixed>>  $raw
     * @return array<int, array{lat: float, lng: float, timestamp: string|null}>
     */
    public function cleanPoints(array $raw): array
    {
        $maxAccuracy = (float) config('tracking.max_accuracy_m');
        $clean = [];

        foreach ($raw as $p) {
            if (isset($p['accuracy']) && (float) $p['accuracy'] > $maxAccuracy) {
                continue;
            }

            $lat = (float) $p['lat'];
            $lng = (float) $p['lng'];
            $last = end($clean);

            // 7 decimals is ~1 cm, well below GPS noise.
            if ($last && round($last['lat'], 7) === round($lat, 7) && round($last['lng'], 7) === round($lng, 7)) {
                continue;
            }

            $clean[] = ['lat' => $lat, 'lng' => $lng, 'timestamp' => $p['timestamp'] ?? null];
        }

        $distinct = count(array_unique(array_map(
            fn ($p) => round($p['lat'], 7).','.round($p['lng'], 7),
            $clean,
        )));
        $min = (int) config('tracking.min_points');

        if ($distinct < $min) {
            throw new PolygonException(
                "At least {$min} distinct points with accuracy better than ".config('tracking.max_accuracy_m').' m are required.',
                ['points' => ["Only {$distinct} usable distinct point(s) after filtering."]],
            );
        }

        return $clean;
    }

    /**
     * @param  array<int, array{lat: float, lng: float, timestamp: string|null}>  $points
     */
    private function insert(User $user, array $data, array $points): int
    {
        // Points are numbered in recorded order so the LineString follows the walk.
        $json = json_encode(array_map(fn ($p) => ['lat' => $p['lat'], 'lng' => $p['lng']], $points));

        $first = $points[0]['timestamp'] ?? null;
        $last = $points[count($points) - 1]['timestamp'] ?? null;

        // 1. LineString from points (lng lat order).
        // 2. Close the ring if first != last.
        // 3. MakeValid, keep polygonal parts only, take the largest (a bow-tie
        //    becomes a MultiPolygon).
        // 4. Insert only when that polygon has real (geography) area - a straight
        //    walk leaves a floating-point sliver, hence the min_area_sqm floor; zero
        //    rows returned => caller reports 422.
        $row = DB::selectOne(<<<'SQL'
            WITH pts AS (
                SELECT t.ord,
                       ST_SetSRID(ST_MakePoint((t.p->>'lng')::float8, (t.p->>'lat')::float8), 4326) AS g
                FROM jsonb_array_elements(?::jsonb) WITH ORDINALITY AS t(p, ord)
            ),
            line AS (
                SELECT ST_MakeLine(g ORDER BY ord) AS track FROM pts
            ),
            ring AS (
                SELECT track,
                       CASE WHEN ST_IsClosed(track) THEN track
                            ELSE ST_AddPoint(track, ST_StartPoint(track)) END AS ring
                FROM line
            ),
            parts AS (
                SELECT (ST_Dump(ST_CollectionExtract(ST_MakeValid(ST_MakePolygon(ring)), 3))).geom AS geom,
                       track
                FROM ring
            ),
            best AS (
                SELECT geom, track FROM parts
                WHERE NOT ST_IsEmpty(geom) AND ST_Area(geom::geography) >= ?::float8
                ORDER BY ST_Area(geom::geography) DESC
                LIMIT 1
            )
            INSERT INTO survey_polygons
                (uuid, user_id, description, geom, track, raw_points, area_sqm, perimeter_m,
                 point_count, started_at, ended_at, source, created_at, updated_at)
            SELECT ?::uuid, ?::bigint, ?::varchar, geom, track, ?::jsonb,
                   ST_Area(geom::geography), ST_Perimeter(geom::geography),
                   ?::int, ?::timestamptz, ?::timestamptz, ?::varchar, now(), now()
            FROM best
            RETURNING id
            SQL, [
            $json,
            (float) config('tracking.min_area_sqm'),
            $data['uuid'],
            $user->id,
            isset($data['description']) ? trim((string) $data['description']) ?: null : null,
            json_encode($data['points']),
            count($points),
            $data['started_at'] ?? $first,
            $data['ended_at'] ?? $last,
            $data['source'] ?? SurveyPolygon::SOURCE_ONLINE,
        ]);

        if (! $row) {
            throw new PolygonException(
                'The tracked path does not enclose any area (empty or zero-area polygon).',
                ['points' => ['The points do not form a polygon with a non-zero area.']],
            );
        }

        return (int) $row->id;
    }
}
