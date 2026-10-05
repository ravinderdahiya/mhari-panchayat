<?php

namespace App\Http\Requests;

// Only checks the envelope (an array of items). Each item is validated
// separately in the controller so one bad track doesn't reject the whole sync.
class BulkStorePolygonRequest extends ApiFormRequest
{
    // Accept both a bare JSON array (the offline queue file) and {"items": [...]}.
    protected function prepareForValidation(): void
    {
        $all = $this->all();
        if ($all !== [] && array_is_list($all)) {
            $this->replace(['items' => $all]);
        }
    }

    public function rules(): array
    {
        return [
            'items' => ['required', 'array', 'min:1', 'max:'.config('tracking.bulk_max')],
            'items.*' => ['array'],
        ];
    }
}
