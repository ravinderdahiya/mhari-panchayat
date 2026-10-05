<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\PolygonException;
use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Http\Requests\ExportShapefileRequest;
use App\Http\Requests\ImportShapefileRequest;
use App\Services\ShapefileService;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

// Shapefile (.shp zip) export / import of the user's polygons via ogr2ogr.
class SurveyPolygonShapefileController extends Controller
{
    use RespondsWithEnvelope;

    public function __construct(private readonly ShapefileService $shapefiles)
    {
    }

    public function export(ExportShapefileRequest $request): BinaryFileResponse|JsonResponse
    {
        $data = $request->validated();

        try {
            $zip = $this->shapefiles->export(
                $request->user(),
                $data['ids'] ?? [],
                $this->parseBbox($request),
                $data['village'] ?? null,
            );
        } catch (PolygonException $e) {
            return $this->fail($e->getMessage(), $e->errors, $e->status);
        }

        return response()
            ->download($zip, 'polygons_'.now()->format('Ymd_His').'.zip', ['Content-Type' => 'application/zip'])
            ->deleteFileAfterSend(true);
    }

    public function import(ImportShapefileRequest $request): JsonResponse
    {
        try {
            $summary = $this->shapefiles->import($request->user(), $request->file('file'));
        } catch (PolygonException $e) {
            return $this->fail($e->getMessage(), $e->errors, $e->status);
        }

        return $this->ok(
            $summary,
            "{$summary['imported']} polygon(s) imported, {$summary['skipped']} feature(s) skipped",
            201,
        );
    }
}
