<?php

namespace App\Services;

use App\Models\Complaint;
use Illuminate\Support\Facades\DB;

/**
 * District ranking by SLA compliance, for the public home page.
 *
 * Each complaint is judged against its priority's SLA hours:
 *   on time = resolved/closed within sla_hours of being filed
 *   breach  = resolved/closed later than that, or still open with its SLA already past
 * Rejected complaints, complaints without a district, and priorities with no SLA are skipped,
 * as are open complaints still inside their SLA window.
 *
 * The counting is one grouped SQL query (the table holds lakhs of rows), not a PHP loop.
 */
class DistrictSlaPerformance
{
    public const MIN_SAMPLE = 3;

    public const LIMIT = 5;

    /** @return list<array{rank: int, district: string, compliance: float, judged: int}> */
    public function top(): array
    {
        $resolved = "complaints.status IN ('Resolved', 'Closed') AND complaints.resolved_at IS NOT NULL";
        $onTime = $this->resolvedWithinSla();

        $rows = Complaint::query()
            ->join('complaint_priorities', 'complaint_priorities.id', '=', 'complaints.priority_id')
            ->join('districts', 'districts.id', '=', 'complaints.district_id')
            ->whereNotNull('complaints.district_id')
            ->where('complaints.status', '!=', 'Rejected')
            ->whereNotNull('complaint_priorities.sla_hours')
            ->groupBy('districts.id', 'districts.name')
            ->selectRaw("districts.name AS district, SUM(CASE WHEN {$resolved} AND {$onTime} THEN 1 ELSE 0 END) AS on_time")
            ->selectRaw(
                "SUM(CASE WHEN {$resolved} THEN 1 WHEN complaints.status NOT IN ('Resolved', 'Closed') AND complaints.sla_due_at < ? THEN 1 ELSE 0 END) AS judged",
                [now()->format('Y-m-d H:i:s')],
            )
            ->get();

        $ranked = $rows
            ->filter(fn ($r) => (int) $r->judged >= self::MIN_SAMPLE)
            ->map(fn ($r) => [
                'district' => $r->district,
                'compliance' => round((int) $r->on_time / (int) $r->judged * 100, 1),
                'judged' => (int) $r->judged,
            ])
            ->sort(fn ($a, $b) => [$b['compliance'], $b['judged'], $a['district']] <=> [$a['compliance'], $a['judged'], $b['district']])
            ->take(self::LIMIT)
            ->values();

        return $ranked->map(fn ($d, $i) => ['rank' => $i + 1] + $d)->all();
    }

    /** SQL: resolved no later than created_at + the priority's SLA hours (PostgreSQL in production, SQLite in tests). */
    private function resolvedWithinSla(): string
    {
        return DB::connection()->getDriverName() === 'sqlite'
            ? "CAST(strftime('%s', complaints.resolved_at) AS INTEGER) <= CAST(strftime('%s', complaints.created_at) AS INTEGER) + complaint_priorities.sla_hours * 3600"
            : "complaints.resolved_at <= complaints.created_at + (complaint_priorities.sla_hours * INTERVAL '1 hour')";
    }
}
