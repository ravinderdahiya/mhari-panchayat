<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\VillageAsset;
use Illuminate\Http\Request;

class VillageAssetController extends Controller
{
    private const GEOMETRY_TYPES = ['Point', 'Line', 'Polygon'];
    private const STATUSES = ['Working', 'Not Working', 'Under Construction'];
    private const CONDITIONS = ['Good', 'Fair', 'Poor'];

    private function storeFile($file, string $subdir): ?string
    {
        if (! $file) {
            return null;
        }

        $path = $file->store("assets/{$subdir}", 'public');

        return asset('storage/'.$path);
    }

    private function rules(): array
    {
        return [
            'village_id' => ['required', 'exists:villages,id'],
            'category' => ['required', 'string'],
            'subtype' => ['required', 'string'],
            'asset_name' => ['required', 'string', 'max:150'],
            'geometry_type' => ['required', 'in:'.implode(',', self::GEOMETRY_TYPES)],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'path' => ['nullable', 'array', 'min:2'],
            'path.*' => ['array', 'size:2'],
            'path.*.*' => ['numeric'],
            'status' => ['nullable', 'in:'.implode(',', self::STATUSES)],
            'condition' => ['nullable', 'in:'.implode(',', self::CONDITIONS)],
            'ward_no' => ['nullable', 'integer'],
            'installed_date' => ['nullable', 'date'],
            'last_inspected' => ['nullable', 'date'],
            'remarks' => ['nullable', 'string'],
            'photo' => ['nullable', 'file', 'image', 'max:15360'],
        ];
    }

    // Photo upload requires multipart/form-data, but that encoding can't
    // cleanly carry a nested array like `path` ([[lat,long], ...]) - the
    // frontend sends it as a JSON string in that case, so decode it back to
    // a real array before validation runs.
    private function decodePathIfJson(Request $request): void
    {
        if ($request->has('path') && is_string($request->input('path'))) {
            $decoded = json_decode($request->input('path'), true);
            if (is_array($decoded)) {
                $request->merge(['path' => $decoded]);
            }
        }
    }

    private function validateGeometry(array $data): ?string
    {
        if ($data['geometry_type'] === 'Point') {
            if (! isset($data['latitude']) || ! isset($data['longitude'])) {
                return 'latitude and longitude are required for a Point asset';
            }
        } else {
            if (empty($data['path']) || count($data['path']) < 2) {
                return 'path (at least 2 points) is required for a Line/Polygon asset';
            }
        }

        return null;
    }

    public function index(Request $request)
    {
        $assets = VillageAsset::with(['village.panchayat', 'creator'])
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['success' => true, 'assets' => $assets]);
    }

    public function show(int $id)
    {
        $asset = VillageAsset::with(['village.panchayat', 'creator'])->findOrFail($id);

        return response()->json(['success' => true, 'asset' => $asset]);
    }

    public function store(Request $request)
    {
        $this->decodePathIfJson($request);
        $data = $request->validate($this->rules());

        if ($error = $this->validateGeometry($data)) {
            return response()->json(['success' => false, 'message' => $error], 400);
        }

        $photoUrl = $this->storeFile($request->file('photo'), 'photos');

        $asset = VillageAsset::create([
            ...$data,
            'photo_url' => $photoUrl,
            'created_by' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'asset' => $asset->fresh(['village.panchayat', 'creator'])], 201);
    }

    public function update(Request $request, int $id)
    {
        $this->decodePathIfJson($request);
        $asset = VillageAsset::findOrFail($id);

        $rules = $this->rules();
        foreach ($rules as $field => $fieldRules) {
            if ($field !== 'photo' && ! str_starts_with($field, 'path')) {
                array_unshift($rules[$field], 'sometimes');
            }
        }
        $data = $request->validate($rules);

        $merged = [...$asset->toArray(), ...$data];
        if ($error = $this->validateGeometry($merged)) {
            return response()->json(['success' => false, 'message' => $error], 400);
        }

        if ($request->hasFile('photo')) {
            $data['photo_url'] = $this->storeFile($request->file('photo'), 'photos');
        }

        $asset->update($data);

        return response()->json(['success' => true, 'asset' => $asset->fresh(['village.panchayat', 'creator'])]);
    }

    public function destroy(int $id)
    {
        VillageAsset::findOrFail($id)->delete();

        return response()->json(['success' => true]);
    }
}
