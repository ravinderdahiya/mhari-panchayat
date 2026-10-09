<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Http\Resources\SurveyPolygonFeatureResource;
use App\Models\SurveyPolygon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

// Admin "Road Map" screen: every user's survey polygons on one map. Routes are
// behind role:admin (admin + super admin only) - unlike /api/polygons, which is
// always scoped to the signed-in user.
class AdminSurveyPolygonController extends Controller
{
    use RespondsWithEnvelope;

    private const MAX_FEATURES = 2000;

    public function index(Request $request): JsonResponse
    {
        $query = $this->filtered($request);

        $total = (clone $query)->count();
        $stats = (clone $query)->toBase()->selectRaw('COALESCE(SUM(survey_polygons.area_sqm), 0) AS area, COUNT(DISTINCT survey_polygons.user_id) AS users')->first();

        $limit = max(1, min(self::MAX_FEATURES, (int) $request->query('limit', self::MAX_FEATURES)));
        $features = $query->withGeoJson(includeTrack: false)->with(['attribute', 'user:id,name,username,role'])
            ->orderByDesc('survey_polygons.created_at')->orderByDesc('survey_polygons.id')
            ->limit($limit)->get()
            ->map(fn (SurveyPolygon $p) => $this->feature($p))
            ->values();

        // Everyone who has a polygon - feeds the "User" filter (not narrowed by the other filters).
        $users = DB::table('survey_polygons')
            ->join('users', 'users.id', '=', 'survey_polygons.user_id')
            ->whereNull('survey_polygons.deleted_at')
            ->groupBy('users.id', 'users.name', 'users.username', 'users.role')
            ->orderBy('users.name')
            ->get(['users.id', 'users.name', 'users.username', 'users.role', DB::raw('COUNT(*) AS polygons')]);

        return $this->ok([
            'type' => 'FeatureCollection',
            'features' => $features,
            'meta' => [
                'total' => $total,
                'returned' => $features->count(),
                'limit' => $limit,
                'total_area_sqm' => (float) $stats->area,
                'users' => (int) $stats->users,
            ],
            'users' => $users,
        ], 'Polygons fetched');
    }

    /** One polygon with its raw walked track (loaded on demand when a polygon is selected). */
    public function show(string $uuid): JsonResponse
    {
        $polygon = SurveyPolygon::query()->withGeoJson()->with(['attribute', 'user:id,name,username,role'])
            ->where('uuid', $uuid)->first();
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }

        return $this->ok($this->feature($polygon), 'Polygon fetched');
    }

    /** @return array<string, mixed> */
    private function feature(SurveyPolygon $polygon): array
    {
        $feature = (new SurveyPolygonFeatureResource($polygon))->resolve();
        $feature['properties']['user'] = $polygon->user ? [
            'id' => $polygon->user->id,
            'name' => $polygon->user->name ?: $polygon->user->username,
            'username' => $polygon->user->username,
            'role' => $polygon->user->role,
        ] : null;

        return $feature;
    }

    /** @return Builder<SurveyPolygon> */
    private function filtered(Request $request): Builder
    {
        $query = SurveyPolygon::query();

        if ($request->filled('user_id') && ctype_digit((string) $request->query('user_id'))) {
            $query->where('survey_polygons.user_id', (int) $request->query('user_id'));
        }

        $source = (string) $request->query('source', '');
        if (in_array($source, [SurveyPolygon::SOURCE_ONLINE, SurveyPolygon::SOURCE_OFFLINE_SYNC, SurveyPolygon::SOURCE_SHP_IMPORT], true)) {
            $query->where('survey_polygons.source', $source);
        }

        // Date range on when the route was recorded, inclusive of both days (India time).
        $from = $this->date($request->query('date_from'));
        $to = $this->date($request->query('date_to'));
        if ($from) {
            $query->whereRaw('COALESCE(survey_polygons.started_at, survey_polygons.created_at) >= ?', [$from->startOfDay()]);
        }
        if ($to) {
            $query->whereRaw('COALESCE(survey_polygons.started_at, survey_polygons.created_at) <= ?', [$to->endOfDay()]);
        }

        // Free-text search over the description, the polygon's attributes and the user.
        $search = trim((string) $request->query('q', ''));
        if ($search !== '') {
            $like = '%'.addcslashes($search, '\\%_').'%';
            $query->where(function (Builder $builder) use ($like) {
                $builder->where('survey_polygons.description', 'ilike', $like)
                    ->orWhereHas('attribute', function ($attribute) use ($like) {
                        $attribute->where('owner_name', 'ilike', $like)
                            ->orWhere('village', 'ilike', $like)
                            ->orWhere('khasra_no', 'ilike', $like)
                            ->orWhere('district', 'ilike', $like)
                            ->orWhere('tehsil', 'ilike', $like);
                    })
                    ->orWhereHas('user', fn ($user) => $user->where('name', 'ilike', $like)->orWhere('username', 'ilike', $like));
            });
        }

        return $query;
    }

    private function date(mixed $value): ?\Carbon\CarbonImmutable
    {
        if (! is_string($value) || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
            return null;
        }

        try {
            return \Carbon\CarbonImmutable::createFromFormat('!Y-m-d', $value, 'Asia/Kolkata') ?: null;
        } catch (\Throwable) {
            return null;
        }
    }
}
