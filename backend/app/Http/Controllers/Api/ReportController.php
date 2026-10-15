<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Models\AssetSurvey;
use App\Models\AssetType;
use App\Models\Complaint;
use App\Services\ComplaintExcelExport;
use App\Support\XlsxWriter;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;

// Admin "Reports" screen: filterable summaries (KPIs, breakdowns, daily trend) of
// complaints and asset surveys. Behind role:admin (admin + super admin), so these
// are always system-wide - no jurisdiction scoping.
class ReportController extends Controller
{
    use RespondsWithEnvelope;

    private const TOP = 10;
    private const MAX_TREND_DAYS = 366;

    // Complaint status -> report bucket (same grouping the mobile app uses).
    private const COMPLAINT_IN_PROGRESS = ['Acknowledged', 'Surveyed', 'In_Progress'];
    private const COMPLAINT_RESOLVED = ['Resolved', 'Closed'];

    // ------------------------------------------------------------------ complaints

    public function complaints(Request $request): JsonResponse
    {
        $base = $this->complaintQuery($request);
        [$from, $to] = $this->trendRange($request);

        $kpi = (clone $base)->toBase()->selectRaw(
            "COUNT(*) AS total,
             COUNT(*) FILTER (WHERE complaints.status = 'Pending') AS pending,
             COUNT(*) FILTER (WHERE complaints.status IN ('Acknowledged','Surveyed','In_Progress')) AS in_progress,
             COUNT(*) FILTER (WHERE complaints.status IN ('Resolved','Closed')) AS resolved,
             COUNT(*) FILTER (WHERE complaints.status = 'Rejected') AS rejected,
             COUNT(*) FILTER (WHERE COALESCE(complaints.escalation_level, 0) > 0) AS escalated,
             COUNT(*) FILTER (WHERE complaints.sla_due_at IS NOT NULL AND (
                 (complaints.resolved_at IS NOT NULL AND complaints.resolved_at > complaints.sla_due_at)
                 OR (complaints.resolved_at IS NULL AND complaints.status NOT IN ('Resolved','Closed','Rejected') AND complaints.sla_due_at < now())
             )) AS sla_breached,
             AVG(EXTRACT(EPOCH FROM (complaints.resolved_at - complaints.created_at)) / 3600) FILTER (WHERE complaints.resolved_at IS NOT NULL) AS avg_resolution_hours,
             AVG(complaints.citizen_rating) AS avg_rating"
        )->first();

        $total = (int) $kpi->total;
        $resolved = (int) $kpi->resolved;

        $named = fn (string $table, string $fk, string $fallback) => (clone $base)->toBase()
            ->leftJoin($table, "{$table}.id", '=', "complaints.{$fk}")
            ->selectRaw("COALESCE({$table}.name, ?) AS name, COUNT(*) AS count", [$fallback])
            ->groupByRaw('1')
            ->orderByDesc('count')->limit(self::TOP)->get()
            ->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count])->values();

        $byStatus = (clone $base)->toBase()->selectRaw('complaints.status AS name, COUNT(*) AS count')
            ->groupBy('complaints.status')->orderByDesc('count')->get()
            ->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count])->values();

        $topResolvers = (clone $base)->toBase()->whereNotNull('complaints.resolved_at')
            ->join('users', 'users.id', '=', 'complaints.assigned_to_id')
            ->selectRaw('users.id, COALESCE(NULLIF(users.name, \'\'), users.username) AS name, users.role, COUNT(*) AS count,
                         AVG(EXTRACT(EPOCH FROM (complaints.resolved_at - complaints.created_at)) / 3600) AS avg_hours')
            ->groupBy('users.id', 'users.name', 'users.username', 'users.role')
            ->orderByDesc('count')->limit(self::TOP)->get()
            ->map(fn ($r) => ['id' => $r->id, 'name' => $r->name, 'role' => $r->role, 'count' => (int) $r->count, 'avg_hours' => round((float) $r->avg_hours, 1)])->values();

        $created = (clone $base)->toBase()->whereBetween('complaints.created_at', [$from, $to])
            ->selectRaw('DATE(complaints.created_at) AS day, COUNT(*) AS count')->groupBy('day')->pluck('count', 'day');
        $resolvedPerDay = (clone $base)->toBase()->whereNotNull('complaints.resolved_at')->whereBetween('complaints.resolved_at', [$from, $to])
            ->selectRaw('DATE(complaints.resolved_at) AS day, COUNT(*) AS count')->groupBy('day')->pluck('count', 'day');

        return $this->ok([
            'kpi' => [
                'total' => $total,
                'pending' => (int) $kpi->pending,
                'in_progress' => (int) $kpi->in_progress,
                'resolved' => $resolved,
                'rejected' => (int) $kpi->rejected,
                'escalated' => (int) $kpi->escalated,
                'sla_breached' => (int) $kpi->sla_breached,
                'resolution_rate' => $total ? round($resolved / $total * 100, 1) : 0.0,
                'avg_resolution_hours' => $kpi->avg_resolution_hours !== null ? round((float) $kpi->avg_resolution_hours, 1) : null,
                'avg_rating' => $kpi->avg_rating !== null ? round((float) $kpi->avg_rating, 2) : null,
            ],
            'by_status' => $byStatus,
            'by_category' => $named('complaint_categories', 'category_id', 'Uncategorised'),
            'by_priority' => $named('complaint_priorities', 'priority_id', 'No priority'),
            'by_department' => $named('departments', 'department_id', 'No department'),
            'by_district' => $named('districts', 'district_id', 'Unknown'),
            'top_resolvers' => $topResolvers,
            'trend' => $this->series($from, $to, ['created' => $created, 'resolved' => $resolvedPerDay]),
            'range' => ['from' => $from->toDateString(), 'to' => $to->toDateString()],
        ], 'Complaint report');
    }

    public function complaintsExport(Request $request, ComplaintExcelExport $exporter)
    {
        $query = $this->complaintQuery($request);

        $total = (clone $query)->count();
        if ($total === 0) {
            return $this->fail('No complaints match the current filters.', [], 404);
        }
        $max = ComplaintExcelExport::MAX_ROWS;
        if ($total > $max) {
            return $this->fail("{$total} complaints match - the Excel export is limited to {$max}. Narrow the filters and try again.", [], 422);
        }

        $complaints = $query->with(['user:id,name,username,mobile', 'assignedTo:id,name,username', 'category:id,name', 'priority:id,name', 'department:id,name', 'assetType:id,name'])
            ->latest('complaints.created_at')->get();

        return response()->download(
            $exporter->build($complaints),
            'complaints-'.now('Asia/Kolkata')->format('Ymd-His').'.xlsx',
            ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
        )->deleteFileAfterSend(true);
    }

    /** @return Builder<Complaint> */
    private function complaintQuery(Request $request): Builder
    {
        $query = Complaint::query();

        foreach (['district_id', 'department_id', 'category_id', 'priority_id'] as $key) {
            if ($request->filled($key) && ctype_digit((string) $request->query($key))) {
                $query->where("complaints.{$key}", (int) $request->query($key));
            }
        }

        $status = (string) $request->query('status', '');
        match ($status) {
            'pending' => $query->where('complaints.status', 'Pending'),
            'in_progress' => $query->whereIn('complaints.status', self::COMPLAINT_IN_PROGRESS),
            'resolved' => $query->whereIn('complaints.status', self::COMPLAINT_RESOLVED),
            'rejected' => $query->where('complaints.status', 'Rejected'),
            default => null,
        };

        $this->applyDateRange($query, 'complaints.created_at', $request);

        return $query;
    }

    // --------------------------------------------------------------- asset surveys

    public function assetSurveys(Request $request): JsonResponse
    {
        $base = $this->surveyQuery($request);
        [$from, $to] = $this->trendRange($request);

        $kpi = (clone $base)->toBase()->selectRaw(
            "COUNT(*) AS total,
             COUNT(DISTINCT asset_surveys.surveyor_id) AS surveyors,
             COUNT(*) FILTER (WHERE asset_surveys.condition = 'GOOD') AS good,
             COUNT(*) FILTER (WHERE asset_surveys.condition = 'FAIR') AS fair,
             COUNT(*) FILTER (WHERE asset_surveys.condition = 'POOR') AS poor,
             COUNT(*) FILTER (WHERE asset_surveys.condition = 'DAMAGED') AS damaged,
             COUNT(*) FILTER (WHERE asset_surveys.review_status = 'submitted') AS submitted,
             COUNT(*) FILTER (WHERE asset_surveys.review_status NOT IN ('submitted','returned','approved','rejected')) AS in_review,
             COUNT(*) FILTER (WHERE asset_surveys.review_status = 'returned') AS returned,
             COUNT(*) FILTER (WHERE asset_surveys.review_status = 'approved') AS approved,
             COUNT(*) FILTER (WHERE asset_surveys.review_status = 'rejected') AS rejected"
        )->first();

        $total = (int) $kpi->total;
        $decided = (int) $kpi->approved + (int) $kpi->rejected;

        $named = fn (string $table, string $fk, string $fallback) => (clone $base)->toBase()
            ->leftJoin($table, "{$table}.id", '=', "asset_surveys.{$fk}")
            ->selectRaw("COALESCE({$table}.name, ?) AS name, COUNT(*) AS count", [$fallback])
            ->groupByRaw('1')
            ->orderByDesc('count')->limit(self::TOP)->get()
            ->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count])->values();

        $grouped = fn (string $column, string $fallback) => (clone $base)->toBase()
            ->selectRaw("COALESCE(NULLIF(asset_surveys.{$column}, ''), ?) AS name, COUNT(*) AS count", [$fallback])
            ->groupByRaw('1')
            ->orderByDesc('count')->limit(self::TOP)->get()
            ->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count])->values();

        $topSurveyors = (clone $base)->toBase()->join('users', 'users.id', '=', 'asset_surveys.surveyor_id')
            ->selectRaw('users.id, COALESCE(NULLIF(users.name, \'\'), users.username) AS name, users.role, COUNT(*) AS count,
                         COUNT(*) FILTER (WHERE asset_surveys.review_status = \'approved\') AS approved,
                         COUNT(*) FILTER (WHERE asset_surveys.review_status IN (\'rejected\', \'returned\')) AS rejected_or_returned')
            ->groupBy('users.id', 'users.name', 'users.username', 'users.role')
            ->orderByDesc('count')->limit(self::TOP)->get()
            ->map(fn ($r) => [
                'id' => $r->id, 'name' => $r->name, 'role' => $r->role, 'count' => (int) $r->count,
                'approved' => (int) $r->approved, 'rejected_or_returned' => (int) $r->rejected_or_returned,
            ])->values();

        $perDay = (clone $base)->toBase()->whereBetween('asset_surveys.survey_date', [$from, $to])
            ->selectRaw('DATE(asset_surveys.survey_date) AS day, COUNT(*) AS count')->groupBy('day')->pluck('count', 'day');

        return $this->ok([
            'kpi' => [
                'total' => $total,
                'surveyors' => (int) $kpi->surveyors,
                'good' => (int) $kpi->good,
                'fair' => (int) $kpi->fair,
                'poor' => (int) $kpi->poor,
                'damaged' => (int) $kpi->damaged,
                'submitted' => (int) $kpi->submitted,
                'in_review' => (int) $kpi->in_review,
                'returned' => (int) $kpi->returned,
                'approved' => (int) $kpi->approved,
                'rejected' => (int) $kpi->rejected,
                'approval_rate' => $decided ? round((int) $kpi->approved / $decided * 100, 1) : 0.0,
            ],
            'asset_stats' => $this->assetStats($request, $base),
            'asset_types' => $this->assetTypeOptions(),
            'by_review_status' => (clone $base)->toBase()->selectRaw('asset_surveys.review_status AS name, COUNT(*) AS count')
                ->groupBy('asset_surveys.review_status')->orderByDesc('count')->get()
                ->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count])->values(),
            'by_condition' => collect(['GOOD', 'FAIR', 'POOR', 'DAMAGED'])->map(fn ($c) => ['name' => $c, 'count' => (int) $kpi->{strtolower($c)}])->values(),
            'by_department' => $named('departments', 'department_id', 'No department'),
            'by_asset_type' => $named('asset_types', 'asset_type_id', 'No type'),
            'by_district' => $grouped('district', 'Unknown'),
            'top_surveyors' => $topSurveyors,
            'trend' => $this->series($from, $to, ['surveys' => $perDay]),
            'range' => ['from' => $from->toDateString(), 'to' => $to->toDateString()],
        ], 'Asset survey report');
    }

    /** @return Builder<AssetSurvey> */
    private function surveyQuery(Request $request): Builder
    {
        $query = AssetSurvey::query();

        foreach (['district_id', 'department_id', 'asset_type_id'] as $key) {
            if ($request->filled($key) && ctype_digit((string) $request->query($key))) {
                $query->where("asset_surveys.{$key}", (int) $request->query($key));
            }
        }

        // One or several asset types: ?asset_type_ids=3,7,12 (none = all types).
        if ($typeIds = $this->idList($request->query('asset_type_ids'))) {
            $query->whereIn('asset_surveys.asset_type_id', $typeIds);
        }

        $condition = strtoupper((string) $request->query('condition', ''));
        if (in_array($condition, ['GOOD', 'FAIR', 'POOR', 'DAMAGED'], true)) {
            $query->where('asset_surveys.condition', $condition);
        }

        $status = strtolower((string) $request->query('review_status', ''));
        if ($status !== '' && preg_match('/^[a-z_]{2,30}$/', $status)) {
            $query->where('asset_surveys.review_status', $status);
        }

        $this->applyDateRange($query, 'asset_surveys.survey_date', $request);

        return $query;
    }

    // ----------------------------------------------------------- asset statistics

    /**
     * Count of surveys for every enlisted asset (asset type) with its department.
     * "Enlisted" = every active asset type attached to an ACTIVE department in master
     * data (today only Panchayati Raj), so assets with no survey yet show up with 0. Honours the same filters as the report;
     * with an asset-type filter only those types are listed.
     *
     * @return array{rows: array<int, array<string, mixed>>, totals: array<string, int>}
     */
    private function assetStats(Request $request, Builder $base): array
    {
        $counts = (clone $base)->toBase()
            ->selectRaw("asset_surveys.department_id, asset_surveys.asset_type_id, COUNT(*) AS total,
                COUNT(*) FILTER (WHERE asset_surveys.condition = 'GOOD') AS good,
                COUNT(*) FILTER (WHERE asset_surveys.condition = 'FAIR') AS fair,
                COUNT(*) FILTER (WHERE asset_surveys.condition = 'POOR') AS poor,
                COUNT(*) FILTER (WHERE asset_surveys.condition = 'DAMAGED') AS damaged")
            ->groupBy('asset_surveys.department_id', 'asset_surveys.asset_type_id')
            ->get()->keyBy(fn ($r) => "{$r->department_id}:{$r->asset_type_id}");

        $typeIds = $this->idList($request->query('asset_type_ids'));
        if ($request->filled('asset_type_id') && ctype_digit((string) $request->query('asset_type_id'))) {
            $typeIds[] = (int) $request->query('asset_type_id');
        }
        $departmentId = $request->filled('department_id') && ctype_digit((string) $request->query('department_id'))
            ? (int) $request->query('department_id') : null;

        $enlisted = DB::table('asset_type_department')
            ->join('asset_types', 'asset_types.id', '=', 'asset_type_department.asset_type_id')
            ->join('departments', 'departments.id', '=', 'asset_type_department.department_id')
            ->where('asset_types.is_active', true)
            ->where('departments.is_active', true)
            ->when($typeIds, fn ($q) => $q->whereIn('asset_types.id', $typeIds))
            ->when($departmentId, fn ($q) => $q->where('departments.id', $departmentId))
            ->get(['departments.id AS department_id', 'departments.name AS department', 'asset_types.id AS asset_type_id', 'asset_types.name AS asset_type']);

        $rows = [];
        foreach ($enlisted as $e) {
            $key = "{$e->department_id}:{$e->asset_type_id}";
            $rows[$key] = ['department_id' => (int) $e->department_id, 'department' => $e->department, 'department_active' => true, 'asset_type_id' => (int) $e->asset_type_id, 'asset_type' => $e->asset_type];
        }

        // Surveys that carry a department/type pair that is not enlisted (e.g. a department that is not
        // active) still count - hiding them would make the totals disagree with the KPIs - and are flagged.
        $missingDepartments = $counts->keys()->reject(fn ($k) => isset($rows[$k]))->map(fn ($k) => (int) explode(':', $k)[0])->unique()->filter()->all();
        $missingTypes = $counts->keys()->reject(fn ($k) => isset($rows[$k]))->map(fn ($k) => (int) explode(':', $k)[1])->unique()->filter()->all();
        $departmentInfo = DB::table('departments')->whereIn('id', $missingDepartments)->get(['id', 'name', 'is_active'])->keyBy('id');
        $typeNames = DB::table('asset_types')->whereIn('id', $missingTypes)->pluck('name', 'id');
        foreach ($counts as $key => $r) {
            if (! isset($rows[$key])) {
                $rows[$key] = [
                    'department_id' => $r->department_id ? (int) $r->department_id : null,
                    'department' => $departmentInfo[$r->department_id]->name ?? 'No department',
                    'department_active' => (bool) ($departmentInfo[$r->department_id]->is_active ?? false),
                    'asset_type_id' => $r->asset_type_id ? (int) $r->asset_type_id : null,
                    'asset_type' => $typeNames[$r->asset_type_id] ?? 'No type',
                ];
            }
        }

        $out = [];
        $totals = ['total' => 0, 'good' => 0, 'fair' => 0, 'poor' => 0, 'damaged' => 0];
        foreach ($rows as $key => $row) {
            $c = $counts->get($key);
            $row += [
                'total' => (int) ($c->total ?? 0), 'good' => (int) ($c->good ?? 0), 'fair' => (int) ($c->fair ?? 0),
                'poor' => (int) ($c->poor ?? 0), 'damaged' => (int) ($c->damaged ?? 0),
            ];
            foreach ($totals as $k => $_) {
                $totals[$k] += $row[$k];
            }
            $out[] = $row;
        }
        usort($out, fn ($a, $b) => [mb_strtolower($a['department']), mb_strtolower($a['asset_type'])] <=> [mb_strtolower($b['department']), mb_strtolower($b['asset_type'])]);

        return ['rows' => $out, 'totals' => $totals];
    }

    /** Active asset types enlisted under an active department (with those departments) - feeds the filter list. @return Collection<int, array<string, mixed>> */
    private function assetTypeOptions(): Collection
    {
        return AssetType::query()->where('is_active', true)
            ->whereHas('departments', fn ($d) => $d->where('departments.is_active', true))
            ->with(['departments' => fn ($d) => $d->where('departments.is_active', true)->select('departments.id', 'departments.name')])
            ->orderBy('sort_order')->orderBy('name')->get(['id', 'name'])
            ->map(fn (AssetType $t) => [
                'id' => $t->id,
                'name' => $t->name,
                'departments' => $t->departments->map(fn ($d) => ['id' => $d->id, 'name' => $d->name])->values(),
            ])->values();
    }

    /** Excel of the asset statistics (department, asset, counts) for the current filters. */
    public function assetStatsExport(Request $request)
    {
        $stats = $this->assetStats($request, $this->surveyQuery($request));

        $sheet = new XlsxWriter('Asset statistics');
        $sheet->addRow(['S.No.', 'Department', 'Asset type', 'Total surveys', 'Good', 'Fair', 'Poor', 'Damaged'], 28);
        foreach ([7, 34, 34, 14, 10, 10, 10, 10] as $col => $width) {
            $sheet->setColumnWidth($col, $width);
        }
        foreach ($stats['rows'] as $i => $r) {
            $sheet->addRow([$i + 1, $r['department'].($r['department_active'] ? '' : ' (inactive)'), $r['asset_type'], $r['total'], $r['good'], $r['fair'], $r['poor'], $r['damaged']]);
        }
        $t = $stats['totals'];
        $sheet->addRow([null, 'TOTAL', count($stats['rows']).' asset types', $t['total'], $t['good'], $t['fair'], $t['poor'], $t['damaged']]);

        $dir = storage_path('app/tmp');
        File::ensureDirectoryExists($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'asset_stats_'.Str::random(16).'.xlsx';
        $sheet->save($path);

        return response()->download($path, 'asset-statistics-'.now('Asia/Kolkata')->format('Ymd-His').'.xlsx', [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ])->deleteFileAfterSend(true);
    }

    /** "3,7,12" -> [3, 7, 12] (digits only, capped). @return array<int, int> */
    private function idList(mixed $value): array
    {
        if (! is_string($value) || $value === '') {
            return [];
        }

        return array_slice(array_values(array_unique(array_map('intval', array_filter(explode(',', $value), 'ctype_digit')))), 0, 300);
    }

    // --------------------------------------------------------------------- helpers

    /** Inclusive date range, with the days read as India time and compared in the DB's timezone (UTC). */
    private function applyDateRange(Builder $query, string $column, Request $request): void
    {
        $from = $this->date($request->query('date_from'));
        $to = $this->date($request->query('date_to'));
        if ($from) {
            $query->where($column, '>=', $from->startOfDay()->setTimezone(config('app.timezone')));
        }
        if ($to) {
            $query->where($column, '<=', $to->endOfDay()->setTimezone(config('app.timezone')));
        }
    }

    /**
     * Window the daily trend covers: the chosen range (capped at a year), otherwise the last 30 days.
     *
     * @return array{0: CarbonImmutable, 1: CarbonImmutable}  in the DB timezone
     */
    private function trendRange(Request $request): array
    {
        $to = $this->date($request->query('date_to')) ?? CarbonImmutable::now('Asia/Kolkata')->startOfDay();
        $from = $this->date($request->query('date_from')) ?? $to->subDays(29);
        if ($from > $to) {
            [$from, $to] = [$to, $from];
        }
        if ($from->diffInDays($to) > self::MAX_TREND_DAYS - 1) {
            $from = $to->subDays(self::MAX_TREND_DAYS - 1);
        }

        return [
            $from->startOfDay()->setTimezone(config('app.timezone')),
            $to->endOfDay()->setTimezone(config('app.timezone')),
        ];
    }

    /**
     * Zero-filled daily series. Keys of each input collection are 'Y-m-d' days
     * (as the DB groups them, i.e. UTC days - fine for a trend chart).
     *
     * @param  array<string, \Illuminate\Support\Collection<string, int>>  $lines
     * @return array<int, array<string, mixed>>
     */
    private function series(CarbonImmutable $from, CarbonImmutable $to, array $lines): array
    {
        $out = [];
        for ($day = $from->startOfDay(); $day <= $to; $day = $day->addDay()) {
            $key = $day->toDateString();
            $row = ['date' => $key];
            foreach ($lines as $name => $counts) {
                $row[$name] = (int) ($counts[$key] ?? 0);
            }
            $out[] = $row;
        }

        return $out;
    }

    private function date(mixed $value): ?CarbonImmutable
    {
        if (! is_string($value) || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
            return null;
        }

        try {
            return CarbonImmutable::createFromFormat('!Y-m-d', $value, 'Asia/Kolkata') ?: null;
        } catch (\Throwable) {
            return null;
        }
    }
}
