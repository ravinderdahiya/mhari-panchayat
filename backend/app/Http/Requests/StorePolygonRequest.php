<?php

namespace App\Http\Requests;

use App\Models\SurveyPolygon;
use App\Models\SurveyPolygonAttribute;
use Illuminate\Validation\Rule;

class StorePolygonRequest extends ApiFormRequest
{
    /**
     * Rules for one polygon payload. Public + static so the bulk endpoint can
     * validate each item on its own and report per-item failures.
     *
     * @return array<string, mixed>
     */
    public static function itemRules(): array
    {
        return [
            'uuid' => ['required', 'uuid'],
            'description' => ['nullable', 'string', 'max:500'],
            'started_at' => ['nullable', 'date'],
            'ended_at' => ['nullable', 'date', 'after_or_equal:started_at'],
            'source' => ['nullable', Rule::in([SurveyPolygon::SOURCE_ONLINE, SurveyPolygon::SOURCE_OFFLINE_SYNC])],
            'points' => ['required', 'array', 'min:'.config('tracking.min_points'), 'max:'.config('tracking.max_points')],
            'points.*.lat' => ['required', 'numeric', 'between:-90,90'],
            'points.*.lng' => ['required', 'numeric', 'between:-180,180'],
            'points.*.accuracy' => ['nullable', 'numeric', 'min:0'],
            'points.*.timestamp' => ['required', 'date'],
            'attributes' => ['nullable', 'array'],
        ] + SurveyPolygonAttribute::rules('attributes.');
    }

    /**
     * validated() drops attribute keys that have no rule (they belong in `extra`),
     * so re-attach the raw attributes object.
     *
     * @param  array<string, mixed>  $validated
     * @param  array<string, mixed>  $raw
     * @return array<string, mixed>
     */
    public static function withRawAttributes(array $validated, array $raw): array
    {
        if (isset($raw['attributes']) && is_array($raw['attributes'])) {
            $validated['attributes'] = $raw['attributes'];
        }

        return $validated;
    }

    public function rules(): array
    {
        return self::itemRules();
    }
}
