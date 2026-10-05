<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

// Attribute data (owner, khasra, crop...) for one SurveyPolygon. Fixed columns
// come from config('survey.attribute_fields'); anything else lands in `extra`.
class SurveyPolygonAttribute extends Model
{
    protected $guarded = [];

    protected $casts = ['extra' => 'array'];

    public function polygon(): BelongsTo
    {
        return $this->belongsTo(SurveyPolygon::class, 'polygon_id');
    }

    /** @return array<int, string> */
    public static function fixedFields(): array
    {
        return array_keys(config('survey.attribute_fields'));
    }

    /**
     * Validation rules for the fixed fields (+ `extra`), optionally under a prefix
     * such as "attributes.". Unknown keys are not validated here; normalize() keeps
     * only safe ones.
     *
     * @return array<string, mixed>
     */
    public static function rules(string $prefix = ''): array
    {
        $rules = [];
        foreach (config('survey.attribute_fields') as $field => $max) {
            $rules[$prefix.$field] = ['nullable', 'string', 'max:'.$max];
        }
        $rules[$prefix.'extra'] = ['nullable', 'array'];

        return $rules;
    }

    /**
     * Split a raw attribute payload into fixed columns and extra jsonb. Keys that
     * are not fixed columns (top level, or inside "extra") go to extra; unsafe
     * keys/values are dropped.
     *
     * @param  array<string, mixed>  $input
     * @return array{fixed: array<string, mixed>, extra: array<string, mixed>}
     */
    public static function normalize(array $input): array
    {
        $fixedKeys = self::fixedFields();
        $fixed = [];
        $extra = [];

        $add = function (string $key, mixed $value) use (&$extra): void {
            if (! preg_match('/^[A-Za-z0-9_]{1,64}$/', $key)) {
                return;
            }
            if (is_scalar($value) || $value === null) {
                $extra[$key] = is_string($value) ? mb_substr($value, 0, 1000) : $value;
            }
        };

        foreach ($input as $key => $value) {
            if (! is_string($key)) {
                continue;
            }
            if (in_array($key, $fixedKeys, true)) {
                $fixed[$key] = is_scalar($value) ? trim((string) $value) : null;
                if ($fixed[$key] === '') {
                    $fixed[$key] = null;
                }
            } elseif ($key === 'extra' && is_array($value)) {
                foreach ($value as $k => $v) {
                    $add((string) $k, $v);
                }
            } else {
                $add($key, $value);
            }
        }

        return ['fixed' => $fixed, 'extra' => $extra];
    }

    /** Create or update (merge) the attribute row for a polygon. */
    public static function upsertFor(int $polygonId, array $input): self
    {
        ['fixed' => $fixed, 'extra' => $extra] = self::normalize($input);

        $row = self::firstOrNew(['polygon_id' => $polygonId]);
        $row->fill($fixed);

        // Merge: provided keys win, null removes a key, others stay.
        $merged = array_merge($row->extra ?? [], $extra);
        $merged = array_filter($merged, fn ($v) => $v !== null);
        $row->extra = $merged ?: null;
        $row->save();

        return $row;
    }
}
