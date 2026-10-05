<?php

namespace App\Http\Requests;

class ExportShapefileRequest extends ApiFormRequest
{
    public function rules(): array
    {
        return [
            'ids' => ['nullable', 'array', 'max:'.config('survey.shp.max_export')],
            'ids.*' => ['integer', 'min:1'],
            'bbox' => ['nullable', 'string', 'max:100'],
            'village' => ['nullable', 'string', 'max:255'],
        ];
    }
}
