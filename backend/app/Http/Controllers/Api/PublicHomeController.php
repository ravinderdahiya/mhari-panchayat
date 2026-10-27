<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppVersion;
use App\Models\AssetSurvey;
use App\Models\AssetType;
use App\Models\Complaint;
use App\Models\Panchayat;
use App\Models\SiteSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

/**
 * Data behind the public (logged-out) home page: platform-wide numbers, a
 * complaint tracker and the approved-asset map. Nothing here needs a login, so
 * it only ever exposes aggregates, one complaint's status to someone who knows
 * both its ID and the filer's mobile number, and approved asset points.
 */
class PublicHomeController extends Controller
{
    // Tracker stages in order; a complaint status decides how far along it is.
    private const STAGES = ['submitted', 'routed', 'assigned', 'under_review', 'resolved', 'closed'];

    private const DONE = ['Resolved', 'Closed', 'Rejected'];

    // Used until an admin saves a store link in App Version.
    private const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=in.hsac.mharipanchayat';

    public function home(): JsonResponse
    {
        $payload = Cache::remember('public.home', 300, function () {
            $resolved = Complaint::whereIn('status', ['Resolved', 'Closed']);
            $avgDays = (clone $resolved)
                ->whereNotNull('resolved_at')
                ->selectRaw('AVG(EXTRACT(EPOCH FROM (resolved_at - created_at)) / 86400) AS d')
                ->value('d');

            $types = AssetType::where('is_active', true)->orderBy('sort_order')->orderBy('name')->get(['name', 'name_hi']);
            $settings = SiteSetting::values();

            return [
                'stats' => [
                    'panchayats' => Panchayat::where('is_active', true)->count(),
                    'complaints_total' => Complaint::count(),
                    'complaints_resolved' => (clone $resolved)->count(),
                    'avg_resolution_days' => $avgDays !== null ? round((float) $avgDays, 1) : null,
                    'assets_geotagged' => AssetSurvey::whereNotNull('latitude')->whereNotNull('longitude')
                        ->where('review_status', '!=', 'rejected')->count(),
                ],
                'asset_types' => [
                    'total' => $types->count(),
                    'featured' => $types->take(8)->map(fn ($t) => ['name' => $t->name, 'name_hi' => $t->name_hi])->values(),
                ],
                'contact' => [
                    'helpline' => $settings['helpline'],
                    'email' => $settings['support_email'],
                    'office_hours' => $settings['office_hours'],
                ],
                'announcement' => $settings['announcement_active'] === '1' && $settings['announcement_title'] !== ''
                    ? collect($settings)
                        ->filter(fn ($v, $k) => str_starts_with($k, 'announcement_') && $k !== 'announcement_active')
                        ->mapWithKeys(fn ($v, $k) => [substr($k, strlen('announcement_')) => $v])
                        ->all()
                    : null,
                'app' => [
                    'android_url' => AppVersion::forPlatform('android')?->store_url ?: self::PLAY_STORE_URL,
                    'ios_url' => AppVersion::forPlatform('ios')?->store_url,
                ],
                'generated_at' => now()->toIso8601String(),
            ];
        });

        return response()->json(['success' => true, 'data' => $payload]);
    }

    public function track(Request $request): JsonResponse
    {
        $data = $request->validate([
            'complaint_id' => ['required', 'string', 'max:40'],
            'mobile' => ['required', 'string', 'regex:/^[6-9]\d{9}$/'],
        ], [
            'mobile.regex' => 'Enter the 10-digit mobile number used to file the complaint.',
        ]);

        $complaint = Complaint::with(['user:id,mobile,username', 'category:id,name', 'timeline'])
            ->where('code', strtoupper(trim($data['complaint_id'])))
            ->first();

        // One answer for "no such complaint" and "not your mobile number", so the
        // endpoint cannot be used to find out which complaint IDs exist.
        $owner = $complaint?->user;
        if (! $complaint || ! $owner || ! in_array($data['mobile'], array_filter([$owner->mobile, $owner->username]), true)) {
            return response()->json([
                'success' => false,
                'message' => 'No complaint found for this ID and mobile number. Check both and try again.',
            ], 404);
        }

        $stage = $this->stageIndex($complaint);
        $firstEvent = fn (array $statuses) => $complaint->timeline
            ->first(fn ($e) => in_array($e->status, $statuses, true))?->created_at;

        $times = [
            'submitted' => $complaint->created_at,
            'routed' => $firstEvent(['Acknowledged', 'Surveyed', 'In_Progress', 'Resolved', 'Closed'])
                ?: ($complaint->assigned_to_id ? $complaint->created_at : null),
            'assigned' => $firstEvent(['Acknowledged']),
            'under_review' => $firstEvent(['Surveyed', 'In_Progress']),
            'resolved' => $complaint->resolved_at ?: $firstEvent(['Resolved']),
            'closed' => $firstEvent(['Closed']),
        ];

        $open = ! in_array($complaint->status, self::DONE, true);

        return response()->json(['success' => true, 'data' => [
            'complaint_id' => $complaint->code,
            'status' => $complaint->status,
            'rejected' => $complaint->status === 'Rejected',
            'category' => $complaint->category?->name,
            'location' => array_values(array_filter([$complaint->village, $complaint->panchayat, $complaint->location_district])),
            'filed_at' => $complaint->created_at?->toIso8601String(),
            'updated_at' => $complaint->updated_at?->toIso8601String(),
            'sla_due_at' => $open ? $complaint->sla_due_at?->toIso8601String() : null,
            'days_left' => $open && $complaint->sla_due_at
                ? (int) ceil(now()->diffInSeconds($complaint->sla_due_at, false) / 86400)
                : null,
            'stage' => $stage,
            'steps' => collect(self::STAGES)->values()->map(fn ($key, $i) => [
                'key' => $key,
                'reached' => $i <= $stage,
                'at' => $i <= $stage ? $times[$key]?->toIso8601String() : null,
            ])->all(),
            // Titles and dates only: event descriptions can carry staff usernames.
            'timeline' => $complaint->timeline->sortByDesc('created_at')->take(10)->map(fn ($e) => [
                'title' => $e->title,
                'status' => $e->status,
                'at' => $e->created_at?->toIso8601String(),
            ])->values(),
        ]]);
    }

    /** Type-ahead for the header search box: panchayats by name, with their block and district. */
    public function search(Request $request): JsonResponse
    {
        $q = trim((string) $request->query('q', ''));
        if (mb_strlen($q) < 2) {
            return response()->json(['success' => true, 'data' => []]);
        }

        $like = '%'.str_replace(['%', '_'], ['\%', '\_'], $q).'%';
        $hits = Panchayat::query()
            ->with('block:id,name,district_id', 'block.district:id,name')
            ->where('is_active', true)
            ->where('name', 'ilike', $like)
            ->orderByRaw('(name ILIKE ?) DESC', [str_replace(['%', '_'], ['\%', '\_'], $q).'%'])
            ->orderBy('name')
            ->limit(8)
            ->get(['id', 'name', 'block_id'])
            ->map(fn (Panchayat $p) => [
                'id' => $p->id,
                'name' => $p->name,
                'block_id' => $p->block?->id,
                'block' => $p->block?->name,
                'district_id' => $p->block?->district?->id,
                'district' => $p->block?->district?->name,
            ]);

        return response()->json(['success' => true, 'data' => $hits]);
    }

    /** Approved asset points for the home page map, optionally narrowed to an area. */
    public function assets(Request $request): JsonResponse
    {
        $filters = $request->validate([
            'district_id' => ['nullable', 'integer'],
            'block_id' => ['nullable', 'integer'],
            'panchayat_id' => ['nullable', 'integer'],
        ]);

        $query = AssetSurvey::query()
            ->where('review_status', 'approved')
            ->whereNotNull('latitude')->whereNotNull('longitude')
            ->with('assetType:id,name,name_hi');
        foreach (['district_id', 'block_id', 'panchayat_id'] as $column) {
            if (! empty($filters[$column])) {
                $query->where($column, $filters[$column]);
            }
        }

        $total = (clone $query)->count();
        $points = $query->orderByDesc('id')->limit(400)->get()->map(fn (AssetSurvey $a) => [
            'id' => $a->id,
            'name' => $a->asset_name,
            'type' => $a->assetType?->name,
            'type_hi' => $a->assetType?->name_hi,
            'village' => $a->village,
            'lat' => (float) $a->latitude,
            'lng' => (float) $a->longitude,
        ]);

        return response()->json(['success' => true, 'data' => ['total' => $total, 'points' => $points]]);
    }

    private function stageIndex(Complaint $complaint): int
    {
        return match ($complaint->status) {
            'Closed' => 5,
            'Resolved' => 4,
            'Surveyed', 'In_Progress' => 3,
            'Acknowledged' => 2,
            'Rejected' => 1,
            default => $complaint->assigned_to_id ? 1 : 0, // Pending / Reopened
        };
    }
}
