<?php

namespace App\Http\Requests;

class ImportShapefileRequest extends ApiFormRequest
{
    public function rules(): array
    {
        return [
            'file' => ['required', 'file', 'mimes:zip', 'max:'.config('survey.shp.max_upload_kb')],
        ];
    }
}
