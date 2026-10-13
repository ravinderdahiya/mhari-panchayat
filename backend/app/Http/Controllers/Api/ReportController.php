<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\RespondsWithEnvelope;
use App\Http\Controllers\Controller;
use App\Models\AssetSurvey;
use App\Models\Complaint;
use App\Services\ComplaintExcelExport;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

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
