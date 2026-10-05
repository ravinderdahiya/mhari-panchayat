<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Http\Requests\UpsertPolygonAttributesRequest;
use App\Http\Resources\SurveyPolygonAttributeResource;
use App\Models\SurveyPolygon;
use App\Models\SurveyPolygonAttribute;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

// Attribute data (owner, khasra, crop...) of a polygon, stored in its own table.
class SurveyPolygonAttributeController extends Controller
{
    use RespondsWithEnvelope;

    public function show(Request $request, string $uuid): JsonResponse
    {
        $polygon = $this->polygon($request, $uuid);
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }

        $attributes = $polygon->attribute;

        return $this->ok(
            $attributes ? (new SurveyPolygonAttributeResource($attributes))->resolve() : null,
            $attributes ? 'Attributes fetched' : 'No attributes saved for this polygon yet',
        );
    }

    // Create or update: provided fixed fields overwrite, omitted ones stay,
    // `extra` (and any unknown key) is merged into the jsonb column.
    public function upsert(UpsertPolygonAttributesRequest $request, string $uuid): JsonResponse
    {
        $polygon = $this->polygon($request, $uuid);
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }

        $existed = $polygon->attribute !== null;
        $row = SurveyPolygonAttribute::upsertFor($polygon->id, $request->all());

        return $this->ok(
            (new SurveyPolygonAttributeResource($row))->resolve(),
            $existed ? 'Attributes updated' : 'Attributes created',
            $existed ? 200 : 201,
        );
    }

    public function destroy(Request $request, string $uuid): JsonResponse
    {
        $polygon = $this->polygon($request, $uuid);
        if (! $polygon) {
            return $this->fail('Polygon not found', [], 404);
        }
        if (! $polygon->attribute) {
            return $this->fail('No attributes saved for this polygon', [], 404);
        }

        $polygon->attribute->delete();

        return $this->ok(null, 'Attributes deleted');
    }

    private function polygon(Request $request, string $uuid): ?SurveyPolygon
    {
        return SurveyPolygon::query()->summary()->with('attribute')
            ->where('survey_polygons.user_id', $request->user()->id)
            ->where('uuid', $uuid)
            ->first();
    }
}
