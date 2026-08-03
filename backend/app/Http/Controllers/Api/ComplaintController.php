<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Complaint;
use App\Models\ComplaintPriority;
use App\Models\ComplaintTimelineEvent;
use App\Models\ComplaintTransfer;
use App\Models\ComplaintCategory;
use App\Models\AssetType;
use App\Models\District;
use App\Models\Tehsil;
use App\Models\User;
use App\Models\Village;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ComplaintController extends Controller
{
    private const WITH = [
        'user', 'assignedTo', 'verifiedBy', 'category', 'priority', 'timeline.performedBy',
        'department:id,name,code', 'assetType:id,name,icon_key',
        'district:id,name', 'tehsil:id,name', 'villageMaster:id,name,panchayat_id',
        'panchayatMaster:id,name',
        'transfers.fromUser', 'transfers.toUser', 'transfers.transferredBy',
        'duplicateOf.category',
    ];

    public function categories(Request $request)
    {
        $assetTypeId = $request->integer('asset_type_id') ?: null;
        $departmentId = $request->integer('department_id') ?: null;
        $query = ComplaintCategory::query()
            ->with('defaultPriority:id,name,level')
            ->whereDoesntHave('children')
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($assetTypeId) {
            $query->where('asset_type_id', $assetTypeId);
            $departmentId
                ? $query->where('department_id', $departmentId)
                : $query->whereNull('department_id');
        } else {
            $query->whereNull('asset_type_id')->whereNull('department_id');
        }

        $districtId = $request->user()->district_id;
        $query->where(function ($scoped) use ($districtId) {
            $scoped->whereNull('district_id');
            if ($districtId) {
                $scoped->orWhere('district_id', $districtId);
            }
        });

        return response()->json([
            'success' => true,
            'categories' => $query->get(['id', 'name', 'code', 'default_priority_id'])
                ->map(fn ($category) => [
                    'id' => $category->id,
                    'name' => str_replace('_', ' ', $category->name),
                    'code' => $category->code,
                    'defaultPriorityId' => $category->default_priority_id,
                ]),
        ]);
    }

    public function formOptions(Request $request)
    {
        $districtId = $request->integer('district_id') ?: null;
        $tehsilId = $request->integer('tehsil_id') ?: null;
        if ($districtId && ! District::whereKey($districtId)->exists()) {
            return response()->json(['success' => false, 'message' => 'Invalid district'], 422);
        }
        if ($tehsilId && ! Tehsil::whereKey($tehsilId)->where('district_id', $districtId)->exists()) {
            return response()->json(['success' => false, 'message' => 'Invalid tehsil for the selected district'], 422);
        }

        $categories = ComplaintCategory::query()
            ->whereDoesntHave('children')
            ->whereNull('asset_type_id')
            ->whereNull('department_id')
            ->where(function ($query) use ($districtId) {
                $query->whereNull('district_id');
                if ($districtId) {
                    $query->orWhere('district_id', $districtId);
                }
            })
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get(['id', 'name', 'code'])
            ->map(fn (ComplaintCategory $category) => [
                'id' => $category->id,
                'name' => str_replace('_', ' ', $category->name),
                'code' => $category->code,
            ]);

        $payload = [
            'districts' => District::orderBy('name')->get(['id', 'name']),
            'categories' => $categories,
            'priorities' => ComplaintPriority::orderBy('level')->orderBy('name')->get(['id', 'name', 'level']),
            'tehsils' => [],
            'villages' => [],
        ];

        if ($districtId) {
            $payload['tehsils'] = Tehsil::where('district_id', $districtId)
                ->orderBy('name')
                ->get(['id', 'name', 'district_id']);
        }

        if ($tehsilId) {
            $payload['villages'] = Village::query()
                ->with([
                    'panchayat:id,name,block_id',
                    'panchayat.block:id,name',
                ])
                ->where('tehsil_id', $tehsilId)
                ->orderBy('name')
                ->get(['id', 'name', 'panchayat_id'])
                ->map(fn (Village $village) => [
                    'id' => $village->id,
                    'name' => $village->name,
                    'panchayatId' => $village->panchayat_id,
                    'panchayatName' => $village->panchayat?->name,
                    'blockId' => $village->panchayat?->block_id,
                    'blockName' => $village->panchayat?->block?->name,
                ]);
        }

        return response()->json(['success' => true, ...$payload]);
    }

    public function mobileReports(Request $request)
    {
        $query = Complaint::query()->with(['category:id,name', 'timeline']);
        if (! in_array($request->user()->role, ['super_admin', 'state_admin', 'district_admin'], true)) {
            $query->where('assigned_to_id', $request->user()->id);
        }
        $complaints = $query->get();
        $resolvedStatuses = ['Resolved', 'Closed'];
        $resolved = $complaints->filter(fn (Complaint $complaint) => in_array($complaint->status, $resolvedStatuses, true));

        $resolutionDays = $resolved->map(function (Complaint $complaint) {
            $event = $complaint->timeline->firstWhere('status', 'Resolved');
            if (! $event?->created_at) {
                return null;
            }

            return $complaint->created_at->diffInSeconds($event->created_at) / 86400;
        })->filter(fn ($days) => $days !== null);

        $categories = $complaints->groupBy('category_id')->map(function ($items) use ($resolvedStatuses) {
            $first = $items->first();
            $complete = $items->filter(fn (Complaint $complaint) => in_array($complaint->status, $resolvedStatuses, true))->count();
            $total = $items->count();

            return [
                'id' => $first->category_id,
                'name' => str_replace('_', ' ', $first->category?->name ?? 'Uncategorised'),
                'resolved' => $complete,
                'total' => $total,
                'percent' => $total > 0 ? round($complete / $total, 4) : 0,
            ];
        })->sortBy('name')->values();

        return response()->json(['success' => true, 'reports' => [
            'resolved' => $resolved->count(),
            'averageResolutionDays' => $resolutionDays->isEmpty()
                ? null
                : round($resolutionDays->average(), 1),
            'categories' => $categories,
        ]]);
    }

    private function storeFile($file, string $subdir): ?string
    {
        if (! $file) {
            return null;
        }

        $path = $file->store("complaints/{$subdir}", 'public');

        return asset('storage/'.$path);
    }

    private function addTimelineEvent(Complaint $complaint, array $data): void
    {
        ComplaintTimelineEvent::create(['complaint_id' => $complaint->id, 'created_at' => now(), ...$data]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'category_id' => ['required', 'exists:complaint_categories,id'],
            'priority_id' => ['required', 'exists:complaint_priorities,id'],
            'department_id' => ['required', 'exists:departments,id'],
            'asset_type_id' => ['required', 'exists:asset_types,id'],
            'district_id' => ['nullable', 'exists:districts,id'],
            'tehsil_id' => ['nullable', 'exists:tehsils,id'],
            'village_id' => ['nullable', 'exists:villages,id'],
            'location_state' => ['nullable', 'string', 'max:150'],
            'location_district' => ['required_without:district_id', 'nullable', 'string', 'max:150'],
            'location_tehsil' => ['nullable', 'string', 'max:150'],
            'location_village' => ['required_without:village_id', 'nullable', 'string', 'max:150'],
            'location_block' => ['nullable', 'string', 'max:150'],
            'description' => ['required', 'string', 'min:10', 'max:2000'],
            'lat' => ['nullable', 'numeric', 'between:-90,90'],
            'long' => ['nullable', 'numeric', 'between:-180,180'],
            'photo' => ['required', 'image', 'mimes:jpeg,jpg,png,webp', 'max:10240'],
            'voice_note' => ['nullable', 'file', 'max:15360'],
        ], [
            'category_id.required' => 'categoryId is required',
            'category_id.exists' => 'Invalid categoryId',
            'priority_id.exists' => 'Invalid priorityId',
            'lat.between' => 'Invalid latitude',
            'long.between' => 'Invalid longitude',
        ]);

        $tehsil = null;
        $village = null;
        if (! empty($data['district_id']) && ! empty($data['tehsil_id']) && ! empty($data['village_id'])) {
            $tehsil = Tehsil::whereKey($data['tehsil_id'])
                ->where('district_id', $data['district_id'])
                ->first();
            if (! $tehsil) {
                return response()->json(['success' => false, 'message' => 'Selected tehsil does not belong to the district'], 422);
            }

            $village = Village::with('panchayat.block')->find($data['village_id']);
            if (! $village?->panchayat ||
                $village->panchayat->block?->district_id !== (int) $data['district_id'] ||
                $village->tehsil_id !== $tehsil->id) {
                return response()->json(['success' => false, 'message' => 'Selected village does not belong to the tehsil'], 422);
            }
        }

        $categoryIsAllowed = ComplaintCategory::whereKey($data['category_id'])
            ->whereDoesntHave('children')
            ->where(function ($query) use ($data) {
                $query->where(function ($global) {
                    $global->whereNull('asset_type_id')->whereNull('department_id');
                })->orWhere(function ($scoped) use ($data) {
                    $scoped->where('asset_type_id', $data['asset_type_id'])
                        ->where('department_id', $data['department_id']);
                });
            })
            ->where(function ($query) use ($data) {
                $query->whereNull('district_id');
                if (! empty($data['district_id'])) {
                    $query->orWhere('district_id', $data['district_id']);
                }
            })
            ->exists();
        if (! $categoryIsAllowed) {
            return response()->json(['success' => false, 'message' => 'Selected category is not available for this district'], 422);
        }

        $assetTypeIsAllowed = AssetType::query()
            ->whereKey($data['asset_type_id'])
            ->where('is_active', true)
            ->whereHas('departments', fn ($query) => $query->where('departments.id', $data['department_id']))
            ->exists();
        if (! $assetTypeIsAllowed) {
            return response()->json(['success' => false, 'message' => 'Selected asset is not available for this department'], 422);
        }

        $beforePhotoUrl = $this->storeFile($request->file('photo'), 'photos');
        $voiceNoteUrl = $this->storeFile($request->file('voice_note'), 'voice-notes');

        // Same category + same village, still open (not Resolved/Rejected/Closed) -
        // a same-location/same-issue-type signal, not a geo-radius calculation.
        $duplicateOfId = null;
        if ($village?->name) {
            $duplicateOfId = Complaint::where('category_id', $data['category_id'])
                ->where('village_id', $village->id)
                ->whereNotIn('status', ['Resolved', 'Rejected', 'Closed'])
                ->orderByDesc('created_at')
                ->value('id');
        }

        $complaint = Complaint::create([
            'user_id' => $request->user()->id,
            'category_id' => $data['category_id'],
            'priority_id' => $data['priority_id'],
            'department_id' => $data['department_id'],
            'asset_type_id' => $data['asset_type_id'],
            'district_id' => $data['district_id'] ?? null,
            'tehsil_id' => $tehsil?->id,
            'village_id' => $village?->id,
            'panchayat_id' => $village?->panchayat_id,
            'village' => $village?->name ?? $data['location_village'] ?? null,
            'panchayat' => $village?->panchayat?->name,
            'location_state' => $data['location_state'] ?? null,
            'location_district' => $data['location_district'] ?? $village?->tehsil?->district?->name,
            'location_tehsil' => $data['location_tehsil'] ?? $tehsil?->name,
            'location_block' => $data['location_block'] ?? $village?->panchayat?->block?->name,
            'description' => $data['description'],
            'lat' => $data['lat'] ?? null,
            'long' => $data['long'] ?? null,
            'status' => 'Pending',
            'before_photo_url' => $beforePhotoUrl,
            'voice_note_url' => $voiceNoteUrl,
            'duplicate_of_id' => $duplicateOfId,
        ]);

        $this->addTimelineEvent($complaint, [
            'status' => 'Pending',
            'title' => 'Complaint Filed',
            'description' => "Filed by {$request->user()->username}",
            'performed_by_id' => $request->user()->id,
            'photo_url' => $beforePhotoUrl,
        ]);

        if ($duplicateOfId) {
            $this->addTimelineEvent($complaint, [
                'status' => 'Pending',
                'title' => 'Flagged as a Possible Repeat',
                'description' => "Flagged as a possible repeat of complaint #{$duplicateOfId}",
                'performed_by_id' => $request->user()->id,
            ]);
        }

        return response()->json([
            'success' => true,
            'message' => 'Complaint submitted successfully',
            'complaint' => $complaint->load(self::WITH),
        ], 201);
    }

    public function index(Request $request)
    {
        $query = Complaint::with(self::WITH)->orderByDesc('created_at');
        if ($request->user()->role === 'citizen') {
            $query->where('user_id', $request->user()->id);
        }

        return response()->json(['success' => true, 'complaints' => $query->get()]);
    }

    public function show(Request $request, int $id)
    {
        $complaint = Complaint::with(self::WITH)->find($id);
        $isOwner = $complaint && $complaint->user_id === $request->user()->id;
        $isStaff = $request->user()->role !== 'citizen';

        if (! $complaint || (! $isOwner && ! $isStaff)) {
            return response()->json(['success' => false, 'message' => 'Complaint not found'], 404);
        }

        return response()->json(['success' => true, 'complaint' => $complaint]);
    }

    public function acknowledge(Request $request, int $id)
    {
        $complaint = Complaint::findOrFail($id);
        if (! in_array($complaint->status, ['Pending', 'Reopened'], true)) {
            return response()->json(['success' => false, 'message' => "Cannot acknowledge a complaint in {$complaint->status} status"], 400);
        }

        $assignedToId = $request->input('assigned_to_id');
        $complaint->update(['status' => 'Acknowledged', 'assigned_to_id' => $assignedToId ?: $complaint->assigned_to_id]);

        $this->addTimelineEvent($complaint, [
            'status' => 'Acknowledged',
            'title' => 'Complaint Acknowledged',
            'description' => $assignedToId ? 'Acknowledged and assigned for field inspection' : 'Acknowledged',
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Complaint acknowledged', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function survey(Request $request, int $id)
    {
        $complaint = Complaint::findOrFail($id);
        if (! in_array($complaint->status, ['Acknowledged', 'Surveyed', 'In_Progress'], true)) {
            return response()->json(['success' => false, 'message' => "Cannot submit a field survey for a complaint in {$complaint->status} status"], 400);
        }

        $data = $request->validate([
            'stage' => ['required', 'in:Before,During,After'],
            'notes' => ['nullable', 'string'],
            'before_photo' => ['nullable', 'file', 'max:15360'],
            'during_photo' => ['nullable', 'file', 'max:15360'],
            'after_photo' => ['nullable', 'file', 'max:15360'],
        ]);

        $stageStatus = ['Before' => 'Surveyed', 'During' => 'In_Progress', 'After' => 'In_Progress'];
        $nextStatus = $stageStatus[$data['stage']];

        $updates = ['status' => $nextStatus, 'assigned_to_id' => $complaint->assigned_to_id ?: $request->user()->id];
        $latestPhoto = null;
        foreach (['before_photo' => 'before_photo_url', 'during_photo' => 'during_photo_url', 'after_photo' => 'after_photo_url'] as $field => $column) {
            if ($request->hasFile($field)) {
                $url = $this->storeFile($request->file($field), 'survey');
                $updates[$column] = $url;
                $latestPhoto = $url;
            }
        }

        $complaint->update($updates);

        $this->addTimelineEvent($complaint, [
            'status' => $nextStatus,
            'title' => 'Field Inspection Submitted',
            'description' => $data['notes'] ?? null,
            'performed_by_id' => $request->user()->id,
            'photo_url' => $latestPhoto,
        ]);

        return response()->json(['success' => true, 'message' => 'Field survey submitted', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function resolve(Request $request, int $id)
    {
        $complaint = Complaint::findOrFail($id);
        if (! in_array($complaint->status, ['In_Progress', 'Surveyed'], true)) {
            return response()->json(['success' => false, 'message' => "Cannot resolve a complaint in {$complaint->status} status"], 400);
        }

        $complaint->update(['status' => 'Resolved']);

        $this->addTimelineEvent($complaint, [
            'status' => 'Resolved',
            'title' => 'Complaint Resolved',
            'description' => $request->input('notes'),
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Complaint marked resolved', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function verify(Request $request, int $id)
    {
        $complaint = Complaint::findOrFail($id);
        if (! in_array($complaint->status, ['Resolved', 'Closed'], true)) {
            return response()->json(['success' => false, 'message' => "Cannot verify a complaint in {$complaint->status} status"], 400);
        }
        if ($complaint->verified_at) {
            return response()->json(['success' => false, 'message' => 'This complaint has already been verified'], 400);
        }

        $data = $request->validate(['notes' => ['nullable', 'string']]);

        $complaint->update(['verified_at' => now(), 'verified_by_id' => $request->user()->id]);

        $this->addTimelineEvent($complaint, [
            'status' => $complaint->status,
            'title' => 'Field Report Verified',
            'description' => $data['notes'] ?? null,
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Field report verified', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function rate(Request $request, int $id)
    {
        $complaint = Complaint::find($id);
        if (! $complaint || $complaint->user_id !== $request->user()->id) {
            return response()->json(['success' => false, 'message' => 'Complaint not found'], 404);
        }
        if ($complaint->status !== 'Resolved') {
            return response()->json(['success' => false, 'message' => 'Only a resolved complaint can be rated'], 400);
        }

        $rating = (int) $request->input('rating');
        if ($rating < 1 || $rating > 5) {
            return response()->json(['success' => false, 'message' => 'Rating must be a number from 1 to 5'], 400);
        }

        $feedback = $request->input('feedback');
        $complaint->update(['citizen_rating' => $rating, 'citizen_feedback' => $feedback, 'status' => 'Closed']);

        $this->addTimelineEvent($complaint, [
            'status' => 'Closed',
            'title' => 'Rated & Closed by Citizen',
            'description' => $feedback,
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Thank you for your feedback', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function transfer(Request $request, int $id)
    {
        $complaint = Complaint::findOrFail($id);
        if (in_array($complaint->status, ['Closed', 'Rejected'], true)) {
            return response()->json(['success' => false, 'message' => "Cannot transfer a complaint in {$complaint->status} status"], 400);
        }

        $data = $request->validate([
            'to_user_id' => ['required', 'exists:users,id'],
            'reason' => ['nullable', 'string'],
        ]);

        $fromUser = $complaint->assigned_to_id ? User::find($complaint->assigned_to_id) : null;
        $toUser = User::findOrFail($data['to_user_id']);

        ComplaintTransfer::create([
            'complaint_id' => $complaint->id,
            'from_user_id' => $fromUser?->id,
            'to_user_id' => $toUser->id,
            'from_department_id' => $fromUser?->department_id,
            'to_department_id' => $toUser->department_id,
            'reason' => $data['reason'] ?? null,
            'transferred_by_id' => $request->user()->id,
            'created_at' => now(),
        ]);

        $complaint->update(['assigned_to_id' => $toUser->id]);

        $this->addTimelineEvent($complaint, [
            'status' => $complaint->status,
            'title' => 'Complaint Transferred',
            'description' => $data['reason'] ?? "Reassigned to {$toUser->username}",
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Complaint transferred', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function reopen(Request $request, int $id)
    {
        $complaint = Complaint::find($id);
        if (! $complaint || $complaint->user_id !== $request->user()->id) {
            return response()->json(['success' => false, 'message' => 'Complaint not found'], 404);
        }
        if ($complaint->status !== 'Closed') {
            return response()->json(['success' => false, 'message' => "Cannot reopen a complaint in {$complaint->status} status"], 400);
        }

        $data = $request->validate(['reason' => ['required', 'string']]);

        $complaint->update(['status' => 'Reopened']);

        $this->addTimelineEvent($complaint, [
            'status' => 'Reopened',
            'title' => 'Complaint Reopened',
            'description' => $data['reason'],
            'performed_by_id' => $request->user()->id,
        ]);

        return response()->json(['success' => true, 'message' => 'Complaint reopened', 'complaint' => $complaint->fresh(self::WITH)]);
    }

    public function reports()
    {
        $total = Complaint::count();
        $byStatus = Complaint::selectRaw('status, count(*) as count')->groupBy('status')->pluck('count', 'status');
        $byCategory = Complaint::join('complaint_categories', 'complaints.category_id', '=', 'complaint_categories.id')
            ->selectRaw('complaint_categories.name as name, count(*) as count')
            ->groupBy('complaint_categories.name')
            ->pluck('count', 'name');

        $today = Complaint::whereDate('created_at', now()->toDateString())->count();
        $thisMonth = Complaint::whereYear('created_at', now()->year)->whereMonth('created_at', now()->month)->count();

        $avgResolutionHours = DB::table('complaint_timeline_events')
            ->join('complaints', 'complaints.id', '=', 'complaint_timeline_events.complaint_id')
            ->where('complaint_timeline_events.status', 'Resolved')
            ->selectRaw('AVG(EXTRACT(EPOCH FROM (complaint_timeline_events.created_at - complaints.created_at)) / 3600) as avg_hours')
            ->value('avg_hours');

        // Last 30 days, zero-filled so the trend line has no gaps.
        $trendStatuses = ['Pending', 'Acknowledged', 'Resolved', 'Closed'];
        $trendRows = DB::table('complaint_timeline_events')
            ->selectRaw('DATE(created_at) as date, status, count(*) as count')
            ->where('created_at', '>=', now()->subDays(29)->startOfDay())
            ->whereIn('status', $trendStatuses)
            ->groupBy('date', 'status')
            ->get()
            ->groupBy('date');

        $trend = [];
        for ($i = 29; $i >= 0; $i--) {
            $date = now()->subDays($i)->toDateString();
            $dayRows = $trendRows->get($date, collect());
            $entry = ['date' => $date];
            foreach ($trendStatuses as $status) {
                $entry[$status] = (int) ($dayRows->firstWhere('status', $status)->count ?? 0);
            }
            $trend[] = $entry;
        }

        $closedByPerson = DB::table('complaint_timeline_events')
            ->join('users', 'users.id', '=', 'complaint_timeline_events.performed_by_id')
            ->join('complaints', 'complaints.id', '=', 'complaint_timeline_events.complaint_id')
            ->where('complaint_timeline_events.status', 'Resolved')
            ->groupBy('users.id', 'users.name', 'users.username')
            ->orderByDesc(DB::raw('count(*)'))
            ->selectRaw('users.id as user_id, users.name, users.username, count(*) as count, AVG(EXTRACT(EPOCH FROM (complaint_timeline_events.created_at - complaints.created_at)) / 3600) as avg_hours')
            ->get()
            ->map(fn ($row) => [
                'user_id' => $row->user_id,
                'name' => $row->name,
                'username' => $row->username,
                'count' => (int) $row->count,
                'avgHours' => round((float) $row->avg_hours, 1),
            ]);

        return response()->json([
            'success' => true,
            'reports' => [
                'total' => $total,
                'pending' => (int) ($byStatus['Pending'] ?? 0),
                'inProgress' => (int) ($byStatus['In_Progress'] ?? 0),
                'completed' => (int) ($byStatus['Resolved'] ?? 0) + (int) ($byStatus['Closed'] ?? 0),
                'rejected' => (int) ($byStatus['Rejected'] ?? 0),
                'today' => $today,
                'thisMonth' => $thisMonth,
                'avgResolutionHours' => $avgResolutionHours ? round((float) $avgResolutionHours, 1) : null,
                'byStatus' => $byStatus,
                'byCategory' => $byCategory,
                'trend' => $trend,
                'closedByPerson' => $closedByPerson,
            ],
        ]);
    }
}
