<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\PolygonException;
use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Http\Requests\BulkStorePolygonRequest;
use App\Http\Requests\StorePolygonRequest;
use App\Http\Resources\SurveyPolygonFeatureResource;
use App\Http\Resources\SurveyPolygonSummaryResource;
use App\Models\SurveyPolygon;
use App\Services\TrackedPolygonService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Throwable;

// GPS-tracked boundaries saved as polygons (PostGIS). Every query is scoped to
// the authenticated user; geometry logic lives in TrackedPolygonService.
class SurveyPolygonController extends Controller
{
    use RespondsWithEnvelope;

    public function __construct(private readonly TrackedPolygonService $service)
    {
    }

    public function store(StorePolygonRequest $request): JsonResponse
    {
        $data = StorePolygonRequest::withRawAttributes($request->validated(), $request->all());

        try {
            [$polygon, $created] = $this->service->store($request->user(), $data);
        } catch (PolygonException $e) {
            return $this->fail($e->getMessage(), $e->errors, $e->status);
        }

        return $this->ok(
            (new SurveyPolygonFeatureResource($polygon))->resolve(),
            $created ? 'Polygon saved' : 'Polygon already exists',
            $created ? 201 : 200,
        );
    }

    public function bulk(BulkStorePolygonRequest $request): JsonResponse
    {
        $user = $request->user();
        $results = [];
        $counts = ['created' => 0, 'duplicate' => 0, 'failed' => 0];

        foreach ($request->validated()['items'] as $index => $item) {
            $result = ['index' => $index, 'uuid' => $item['uuid'] ?? null];

            $validator = Validator::make($item, StorePolygonRequest::itemRules());
            if ($validator->fails()) {
                $result += ['status' => 'failed', 'error' => 'Validation failed', 'errors' => $validator->errors()];
                $counts['failed']++;
                $results[] = $result;

                continue;
            }

            try {
                [$polygon, $created] = $this->service->store($user, StorePolygonRequest::withRawAttributes($validator->validated(), $item));
                $result += [
                    'status' => $created ? 'created' : 'duplicate',
                    'data' => (new SurveyPolygonSummaryResource($polygon))->resolve(),
                ];
                $counts[$created ? 'created' : 'duplicate']++;
            } catch (PolygonException $e) {
                $result += ['status' => 'failed', 'error' => $e->getMessage(), 'errors' => $e->errors];
                $counts['failed']++;
            } catch (Throwable $e) {
                report($e);
                $result += ['status' => 'failed', 'error' => 'Unexpected error while saving this item'];
                $counts['failed']++;
            }

            $results[] = $result;
        }

        return $this->ok(
            ['summary' => $counts, 'results' => $results],
            "{$counts['created']} created, {$counts['duplicate']} duplicate, {$counts['failed']} failed",
        );
    }

    public function index(Request $request): JsonResponse
    {
        $query = $this->filtered($request)->summary()->with('attribute')
            ->orderByDesc('survey_polygons.created_at')->orderByDesc('survey_polygons.id');

        $page = $query->paginate(max(1, min(100, (int) $request->query('per_page', 20))));

        return response()->json([
            'success' => true,
            'message' => 'Polygons fetched',
            'data' => SurveyPolygonSummaryResource::collection($page->getCollection())->resolve(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function show(Request $request, string $uuid): JsonResponse
    {
        $polygon = $this->mine($request)->withGeoJson()->with('attribute')->where('uuid', $uuid)->first();
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }

        return $this->ok((new SurveyPolygonFeatureResource($polygon))->resolve(), 'Polygon fetched');
    }

    public function geojson(Request $request): JsonResponse
    {
        $features = $this->filtered($request)->withGeoJson(includeTrack: false)->with('attribute')
            ->orderByDesc('survey_polygons.created_at')
            ->limit((int) config('tracking.geojson_limit'))->get()
            ->map(fn (SurveyPolygon $p) => (new SurveyPolygonFeatureResource($p))->resolve())
            ->values();

        return $this->ok(['type' => 'FeatureCollection', 'features' => $features], 'Polygons fetched');
    }

    public function destroy(Request $request, string $uuid): JsonResponse
    {
        $polygon = $this->mine($request)->summary()->where('uuid', $uuid)->first();
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }

        $polygon->delete();

        return $this->ok(null, 'Polygon deleted');
    }

    /** @return Builder<SurveyPolygon> */
    private function mine(Request $request): Builder
    {
        return SurveyPolygon::query()->where('survey_polygons.user_id', $request->user()->id);
    }

    /** User's polygons narrowed by ?bbox=, ?village= and ?has_data=. @return Builder<SurveyPolygon> */
    private function filtered(Request $request): Builder
    {
        $query = $this->mine($request);

        if ($bbox = $this->parseBbox($request)) {
            $query->intersectsBbox(...$bbox);
        }

        if ($village = $request->query('village')) {
            $village = (string) $village;
            $query->whereHas('attribute', fn ($q) => $q->whereRaw('lower(village) = lower(?)', [$village]));
        }

        $hasData = $request->query('has_data');
        if ($hasData !== null && $hasData !== '') {
            $flag = filter_var($hasData, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
            if ($flag === null) {
                abort($this->fail('Validation failed', ['has_data' => ['has_data must be true or false.']], 422));
            }
            $flag ? $query->whereHas('attribute') : $query->whereDoesntHave('attribute');
        }

        return $query;
    }
}
