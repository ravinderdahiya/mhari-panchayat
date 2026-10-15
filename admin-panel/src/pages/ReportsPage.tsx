import { useEffect, useMemo, useRef, useState } from 'react';
import { Chart as ChartJS, ArcElement, BarElement, CategoryScale, Legend, LineElement, LinearScale, PointElement, Tooltip } from 'chart.js';
import { Bar, Doughnut, Line } from 'react-chartjs-2';
import { ChevronDown, Download, FileBarChart, Search } from 'lucide-react';
import * as api from '../services/api';
import type { AssetStatRow, AssetSurveyReport, ComplaintReport, ReportCount } from '../services/api';
import type { AssetSurveyReviewStatus } from '../types';

ChartJS.register(ArcElement, BarElement, CategoryScale, Legend, LineElement, LinearScale, PointElement, Tooltip);

type Tab = 'surveys' | 'complaints';

const INPUT = 'w-full text-xs border border-line rounded-lg px-3 py-2 bg-white outline-none focus:ring-2 focus:ring-accent/30';

// Fixed palette (never re-cycled per filter): green, gold, blue, red, violet, teal, orange, slate.
const PALETTE = ['#16a34a', '#C68A16', '#2563eb', '#dc2626', '#7c3aed', '#0d9488', '#ea580c', '#64748b', '#db2777', '#0891b2'];

const REVIEW_LABEL: Record<string, string> = {
  submitted: 'Submitted (not yet forwarded)',
  pending: 'Pending review',
  returned: 'Returned for correction',
  gram_sachiv_reviewed: 'Reviewed by Gram Sachiv',
  gram_sachiv_approved: 'Forwarded by Gram Sachiv',
  bdpo_reviewed: 'Reviewed by BDPO',
  bdpo_forwarded: 'Forwarded by BDPO',
  ddpo_reviewed: 'Reviewed by DDPO',
  ddpo_approved: 'Approved by DDPO',
  xen_reviewed: 'Reviewed by XEN-PR',
  xen_forwarded: 'Forwarded by XEN-PR',
  approved: 'Final approved',
  rejected: 'Rejected',
};

const CONDITION_COLOR: Record<string, string> = { GOOD: '#16a34a', FAIR: '#2563eb', POOR: '#C68A16', DAMAGED: '#dc2626' };
const COMPLAINT_STATUS_COLOR: Record<string, string> = {
  Pending: '#dc2626', Acknowledged: '#C68A16', Surveyed: '#7c3aed', In_Progress: '#ea580c', Resolved: '#16a34a', Closed: '#0d9488', Rejected: '#64748b',
};

const num = (value: number) => value.toLocaleString('en-IN');

function formatHours(hours: number | null) {
  if (hours == null) return '—';
  if (hours < 24) return `${hours.toLocaleString('en-IN', { maximumFractionDigits: 1 })} h`;
  const days = Math.floor(hours / 24);
  const rest = Math.round(hours - days * 24);
  return `${days} d${rest ? ` ${rest} h` : ''}`;
}

const dayLabel = (iso: string) => new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short' }).format(new Date(`${iso}T00:00:00`));

const SURVEY_STATUSES: { value: AssetSurveyReviewStatus | ''; label: string }[] = [
  { value: '', label: 'All statuses' },
  ...Object.entries(REVIEW_LABEL).map(([value, label]) => ({ value: value as AssetSurveyReviewStatus, label })),
];

export default function ReportsPage() {
  const [tab, setTab] = useState<Tab>('surveys');
  const [districts, setDistricts] = useState<{ id: number; name: string }[]>([]);

  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [districtId, setDistrictId] = useState('');
  const [condition, setCondition] = useState('ALL');
  const [reviewStatus, setReviewStatus] = useState<AssetSurveyReviewStatus | ''>('');
  const [assetTypeIds, setAssetTypeIds] = useState<string[]>([]);
  const [assetTypeOptions, setAssetTypeOptions] = useState<AssetSurveyReport['asset_types']>([]);
  const [complaintStatus, setComplaintStatus] = useState('');

  const [surveyReport, setSurveyReport] = useState<AssetSurveyReport | null>(null);
  const [complaintReport, setComplaintReport] = useState<ComplaintReport | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [exporting, setExporting] = useState(false);
  const [exportingStats, setExportingStats] = useState(false);

  useEffect(() => {
    api.getDistricts().then((r) => setDistricts(r.districts)).catch(() => setDistricts([]));
  }, []);

  const filtersActive = dateFrom !== '' || dateTo !== '' || districtId !== ''
    || (tab === 'surveys' ? condition !== 'ALL' || reviewStatus !== '' || assetTypeIds.length > 0 : complaintStatus !== '');
  const clearFilters = () => { setDateFrom(''); setDateTo(''); setDistrictId(''); setCondition('ALL'); setReviewStatus(''); setAssetTypeIds([]); setComplaintStatus(''); };

  // Reload the active report whenever its filters change.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    const timer = window.setTimeout(() => {
      const request = tab === 'surveys'
        ? api.getAssetSurveyReport({ dateFrom, dateTo, districtId, condition, reviewStatus: reviewStatus || undefined, assetTypeIds }).then((r) => { if (!cancelled) { setSurveyReport(r); setAssetTypeOptions(r.asset_types); } })
        : api.getComplaintReport({ dateFrom, dateTo, districtId, status: complaintStatus }).then((r) => { if (!cancelled) setComplaintReport(r); });
      request
        .catch((err) => { if (!cancelled) setError((err as Error).message); })
        .finally(() => { if (!cancelled) setLoading(false); });
    }, 200);
    return () => { cancelled = true; window.clearTimeout(timer); };
  }, [tab, dateFrom, dateTo, districtId, condition, reviewStatus, assetTypeIds, complaintStatus]);

  const handleExport = async () => {
    setExporting(true);
    setError('');
    try {
      if (tab === 'surveys') await api.downloadAssetSurveysExcel({ dateFrom, dateTo, districtId, condition, reviewStatus: reviewStatus || undefined, assetTypeIds });
      else await api.downloadComplaintsExcel({ dateFrom, dateTo, districtId, status: complaintStatus });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setExporting(false);
    }
  };

  const handleStatsExport = async () => {
    setExportingStats(true);
    setError('');
    try {
      await api.downloadAssetStatsExcel({ dateFrom, dateTo, districtId, condition, reviewStatus: reviewStatus || undefined, assetTypeIds });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setExportingStats(false);
    }
  };

  const range = (tab === 'surveys' ? surveyReport : complaintReport)?.range;
  const hasData = tab === 'surveys' ? (surveyReport?.kpi.total ?? 0) > 0 : (complaintReport?.kpi.total ?? 0) > 0;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="inline-flex bg-white border border-line rounded-xl p-1">
          {([['surveys', 'Asset Surveys'], ['complaints', 'Complaints']] as [Tab, string][]).map(([id, label]) => (
            <button key={id} type="button" onClick={() => setTab(id)}
              className={`px-4 py-2 rounded-lg text-xs font-bold cursor-pointer ${tab === id ? 'bg-accent text-white' : 'text-ink hover:bg-cream'}`}>
              {label}
            </button>
          ))}
        </div>
        <button type="button" onClick={handleExport} disabled={exporting || loading || !hasData}
          title="Download the records matching the current filters as an Excel file"
          className="flex items-center gap-1.5 bg-accent hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer disabled:cursor-not-allowed">
          <Download className="w-3.5 h-3.5" /> {exporting ? 'Preparing Excel…' : `Export ${tab === 'surveys' ? 'surveys' : 'complaints'} (Excel)`}
        </button>
      </div>

      <div className="bg-white border border-line rounded-xl p-3 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3 items-end">
        <Field label="Start date">
          <input type="date" value={dateFrom} max={dateTo || undefined} onChange={(e) => setDateFrom(e.target.value)} className={INPUT} />
        </Field>
        <Field label="End date">
          <input type="date" value={dateTo} min={dateFrom || undefined} onChange={(e) => setDateTo(e.target.value)} className={INPUT} />
        </Field>
        <Field label="District">
          <select value={districtId} onChange={(e) => setDistrictId(e.target.value)} className={INPUT}>
            <option value="">All districts</option>
            {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </select>
        </Field>
        {tab === 'surveys' ? (
          <>
            <Field label="Condition">
              <select value={condition} onChange={(e) => setCondition(e.target.value)} className={INPUT}>
                <option value="ALL">All conditions</option><option value="GOOD">Good</option><option value="FAIR">Fair</option>
                <option value="POOR">Poor</option><option value="DAMAGED">Damaged</option>
              </select>
            </Field>
            <Field label="Review status">
              <select value={reviewStatus} onChange={(e) => setReviewStatus(e.target.value as AssetSurveyReviewStatus | '')} className={INPUT}>
                {SURVEY_STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </Field>
            <Field label="Asset type">
              <AssetTypeFilter options={assetTypeOptions} selected={assetTypeIds} onChange={setAssetTypeIds} />
            </Field>
          </>
        ) : (
          <Field label="Status">
            <select value={complaintStatus} onChange={(e) => setComplaintStatus(e.target.value)} className={INPUT}>
              <option value="">All statuses</option><option value="pending">Pending</option><option value="in_progress">In progress</option>
              <option value="resolved">Resolved / closed</option><option value="rejected">Rejected</option>
            </select>
          </Field>
        )}
        <button type="button" onClick={clearFilters} disabled={!filtersActive}
          className="text-xs font-semibold text-accent border border-line rounded-lg px-3 py-2 bg-white hover:bg-cream disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
          Clear filters
        </button>
      </div>

      {error && <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">{error}</p>}
      {loading && <p className="text-xs text-muted">Loading report…</p>}

      {tab === 'surveys' && surveyReport && <SurveyReportView report={surveyReport} dim={loading} onDownloadStats={handleStatsExport} downloadingStats={exportingStats} />}
      {tab === 'complaints' && complaintReport && <ComplaintReportView report={complaintReport} dim={loading} />}

      {range && <p className="text-[11px] text-muted">Daily trend covers {dayLabel(range.from)} – {dayLabel(range.to)} {dateFrom || dateTo ? '(selected dates)' : '(last 30 days)'}; every other number covers {dateFrom || dateTo ? 'the selected dates' : 'all time'}.</p>}
    </div>
  );
}

// ------------------------------------------------------------------ asset surveys

function SurveyReportView({ report, dim, onDownloadStats, downloadingStats }: { report: AssetSurveyReport; dim: boolean; onDownloadStats: () => void; downloadingStats: boolean }) {
  const { kpi } = report;
  const trend = useMemo(() => ({
    labels: report.trend.map((p) => dayLabel(p.date)),
    datasets: [{ label: 'Surveys', data: report.trend.map((p) => p.surveys ?? 0), borderColor: '#16a34a', backgroundColor: '#16a34a', tension: 0.3, pointRadius: 2 }],
  }), [report.trend]);

  return (
    <div className={`space-y-4 ${dim ? 'opacity-60' : ''}`}>
      <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-3">
        <Kpi label="Total surveys" value={num(kpi.total)} />
        <Kpi label="Surveyors" value={num(kpi.surveyors)} />
        <Kpi label="Final approved" value={num(kpi.approved)} tone="green" />
        <Kpi label="In review" value={num(kpi.in_review + kpi.submitted)} tone="amber" />
        <Kpi label="Returned" value={num(kpi.returned)} tone="amber" />
        <Kpi label="Rejected" value={num(kpi.rejected)} tone="red" />
        <Kpi label="Poor / damaged" value={num(kpi.poor + kpi.damaged)} tone="red" />
        <Kpi label="Approval rate" value={`${kpi.approval_rate}%`} hint="approved ÷ (approved + rejected)" />
      </div>

      <AssetStatistics stats={report.asset_stats} onDownload={onDownloadStats} downloading={downloadingStats} />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <Card title="Surveys per day" className="xl:col-span-2"><div className="h-64"><Line data={trend} options={LINE_OPTIONS} /></div></Card>
        <Card title="By condition">
          <DoughnutWithLegend rows={report.by_condition} colorOf={(name, i) => CONDITION_COLOR[name] ?? PALETTE[i % PALETTE.length]!} />
        </Card>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <Card title="By review status">
          <HorizontalBars rows={report.by_review_status.map((r) => ({ ...r, name: REVIEW_LABEL[r.name] ?? r.name }))} />
        </Card>
        <Card title="By asset type (top 10)"><HorizontalBars rows={report.by_asset_type} /></Card>
        <Card title="By department"><HorizontalBars rows={report.by_department} /></Card>
        <Card title="By district (top 10)"><HorizontalBars rows={report.by_district} /></Card>
      </div>

      <Card title="Top surveyors">
        <Table
          head={['Surveyor', 'Role', 'Surveys', 'Approved', 'Rejected / returned']}
          rows={report.top_surveyors.map((s) => [s.name, s.role.replace(/_/g, ' '), num(s.count), num(s.approved), num(s.rejected_or_returned)])}
          empty="No surveys for these filters."
        />
      </Card>
    </div>
  );
}

// -------------------------------------------------------------------- complaints

function ComplaintReportView({ report, dim }: { report: ComplaintReport; dim: boolean }) {
  const { kpi } = report;
  const trend = useMemo(() => ({
    labels: report.trend.map((p) => dayLabel(p.date)),
    datasets: [
      { label: 'Raised', data: report.trend.map((p) => p.created ?? 0), borderColor: '#dc2626', backgroundColor: '#dc2626', tension: 0.3, pointRadius: 2 },
      { label: 'Resolved', data: report.trend.map((p) => p.resolved ?? 0), borderColor: '#16a34a', backgroundColor: '#16a34a', tension: 0.3, pointRadius: 2 },
    ],
  }), [report.trend]);

  return (
    <div className={`space-y-4 ${dim ? 'opacity-60' : ''}`}>
      <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-9 gap-3">
        <Kpi label="Total complaints" value={num(kpi.total)} />
        <Kpi label="Pending" value={num(kpi.pending)} tone="red" />
        <Kpi label="In progress" value={num(kpi.in_progress)} tone="amber" />
        <Kpi label="Resolved" value={num(kpi.resolved)} tone="green" />
        <Kpi label="Rejected" value={num(kpi.rejected)} />
        <Kpi label="Resolution rate" value={`${kpi.resolution_rate}%`} hint="resolved ÷ total" />
        <Kpi label="Avg resolution time" value={formatHours(kpi.avg_resolution_hours)} />
        <Kpi label="SLA breached" value={num(kpi.sla_breached)} tone="red" hint={`${num(kpi.escalated)} escalated`} />
        <Kpi label="Avg citizen rating" value={kpi.avg_rating != null ? `${kpi.avg_rating} / 5` : '—'} />
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <Card title="Complaints per day" className="xl:col-span-2"><div className="h-64"><Line data={trend} options={{ ...LINE_OPTIONS, plugins: { legend: { display: true, position: 'bottom' } } }} /></div></Card>
        <Card title="By status">
          <DoughnutWithLegend rows={report.by_status.map((r) => ({ ...r, name: r.name.replace(/_/g, ' ') }))}
            colorOf={(name, i) => COMPLAINT_STATUS_COLOR[name.replace(/ /g, '_')] ?? PALETTE[i % PALETTE.length]!} />
        </Card>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <Card title="By category (top 10)"><HorizontalBars rows={report.by_category} /></Card>
        <Card title="By district (top 10)"><HorizontalBars rows={report.by_district} /></Card>
        <Card title="By department"><HorizontalBars rows={report.by_department} /></Card>
        <Card title="By priority"><HorizontalBars rows={report.by_priority} /></Card>
      </div>

      <Card title="Top resolvers">
        <Table
          head={['Officer', 'Role', 'Resolved', 'Avg resolution time']}
          rows={report.top_resolvers.map((o) => [o.name, o.role.replace(/_/g, ' '), num(o.count), formatHours(o.avg_hours)])}
          empty="No resolved complaints for these filters."
        />
      </Card>
    </div>
  );
}

// --------------------------------------------------------------------- building blocks

const LINE_OPTIONS = {
  animation: false as const,
  maintainAspectRatio: false,
  interaction: { mode: 'index' as const, intersect: false },
  plugins: { legend: { display: false } },
  scales: { y: { beginAtZero: true, ticks: { precision: 0 } }, x: { ticks: { maxTicksLimit: 10 } } },
};

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-[10px] font-semibold uppercase tracking-wide text-muted mb-1">{label}</span>
      {children}
    </label>
  );
}

function Kpi({ label, value, tone, hint }: { label: string; value: string; tone?: 'green' | 'amber' | 'red'; hint?: string }) {
  const color = tone === 'green' ? 'text-emerald-700' : tone === 'amber' ? 'text-amber-700' : tone === 'red' ? 'text-red-700' : 'text-ink';
  return (
    <div className="bg-white border border-line rounded-xl p-3.5" title={hint}>
      <p className={`text-xl font-semibold leading-tight ${color}`}>{value}</p>
      <p className="text-[11px] text-muted mt-0.5">{label}</p>
      {hint && <p className="text-[10px] text-muted/80 mt-0.5 truncate">{hint}</p>}
    </div>
  );
}

function Card({ title, children, className = '' }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={`bg-white border border-line rounded-xl p-4 ${className}`}>
      <h3 className="text-xs font-bold text-muted uppercase tracking-wide mb-3 flex items-center gap-1.5"><FileBarChart className="w-3.5 h-3.5" />{title}</h3>
      {children}
    </div>
  );
}

function HorizontalBars({ rows }: { rows: ReportCount[] }) {
  if (rows.length === 0 || rows.every((r) => r.count === 0)) return <p className="text-xs text-muted py-6 text-center">No data for these filters.</p>;
  return (
    <div style={{ height: Math.max(140, rows.length * 34 + 30) }}>
      <Bar
        data={{
          labels: rows.map((r) => (r.name.length > 34 ? `${r.name.slice(0, 33)}…` : r.name)),
          datasets: [{ data: rows.map((r) => r.count), backgroundColor: '#C68A16', borderRadius: 4, barThickness: 16 }],
        }}
        options={{
          indexAxis: 'y',
          animation: false,
          maintainAspectRatio: false,
          plugins: { legend: { display: false }, tooltip: { callbacks: { title: (items) => rows[items[0]!.dataIndex]!.name } } },
          scales: { x: { beginAtZero: true, ticks: { precision: 0 } }, y: { grid: { display: false } } },
        }}
      />
    </div>
  );
}

function DoughnutWithLegend({ rows, colorOf }: { rows: ReportCount[]; colorOf: (name: string, index: number) => string }) {
  const visible = rows.filter((r) => r.count > 0);
  if (visible.length === 0) return <p className="text-xs text-muted py-6 text-center">No data for these filters.</p>;
  const total = visible.reduce((sum, r) => sum + r.count, 0);
  return (
    <div className="flex flex-col sm:flex-row xl:flex-col items-center gap-4">
      <div className="w-40 h-40 shrink-0">
        <Doughnut
          data={{ labels: visible.map((r) => r.name), datasets: [{ data: visible.map((r) => r.count), backgroundColor: visible.map((r, i) => colorOf(r.name, i)), borderColor: '#fcfcfb', borderWidth: 2 }] }}
          options={{ animation: false, plugins: { legend: { display: false } }, cutout: '62%' }}
        />
      </div>
      <ul className="flex-1 w-full space-y-1.5">
        {visible.map((r, i) => (
          <li key={r.name} className="flex items-center justify-between text-xs">
            <span className="flex items-center gap-2"><span className="w-2.5 h-2.5 rounded-full" style={{ background: colorOf(r.name, i) }} /><span className="text-ink font-medium">{r.name}</span></span>
            <span className="text-muted tabular-nums">{num(r.count)} · {Math.round((r.count / total) * 100)}%</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Table({ head, rows, empty }: { head: string[]; rows: string[][]; empty: string }) {
  if (rows.length === 0) return <p className="text-xs text-muted py-4 text-center">{empty}</p>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-xs">
        <thead className="text-[10px] uppercase tracking-wide text-muted border-b border-line"><tr>{head.map((h, i) => <th key={h} className={`py-2 pr-4 ${i >= 2 ? 'text-right' : ''}`}>{h}</th>)}</tr></thead>
        <tbody className="divide-y divide-line">
          {rows.map((row, i) => (
            <tr key={i}>{row.map((cell, j) => <td key={j} className={`py-2 pr-4 ${j >= 2 ? 'text-right tabular-nums' : ''} ${j === 0 ? 'font-medium text-ink' : 'text-muted'}`}>{cell}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ----------------------------------------------------------- asset type filter + statistics

/** "All asset types", or tick one / several. Searchable; closes on an outside click. */
function AssetTypeFilter({ options, selected, onChange }: {
  options: AssetSurveyReport['asset_types']; selected: string[]; onChange: (ids: string[]) => void;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return undefined;
    const close = (event: MouseEvent) => { if (!rootRef.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', close);
    return () => document.removeEventListener('mousedown', close);
  }, [open]);

  const chosen = useMemo(() => new Set(selected), [selected]);
  const visible = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return needle
      ? options.filter((o) => o.name.toLowerCase().includes(needle) || o.departments.some((d) => d.name.toLowerCase().includes(needle)))
      : options;
  }, [options, search]);

  const toggle = (id: string) => onChange(chosen.has(id) ? selected.filter((x) => x !== id) : [...selected, id]);
  const label = selected.length === 0
    ? 'All asset types'
    : selected.length === 1 ? (options.find((o) => String(o.id) === selected[0])?.name ?? '1 selected') : `${selected.length} asset types`;

  return (
    <div ref={rootRef} className="relative">
      <button type="button" onClick={() => setOpen((v) => !v)} disabled={options.length === 0}
        className={`${INPUT} flex items-center justify-between gap-2 text-left cursor-pointer disabled:opacity-60`}>
        <span className="truncate">{label}</span><ChevronDown className="w-3.5 h-3.5 shrink-0 text-muted" />
      </button>
      {open && (
        <div className="absolute right-0 z-30 mt-1 w-80 max-w-[85vw] bg-white border border-line rounded-xl shadow-lg">
          <div className="p-2 border-b border-line">
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted" />
              <input autoFocus value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search asset type or department"
                className="w-full text-xs border border-line rounded-lg pl-8 pr-2 py-1.5 outline-none focus:ring-2 focus:ring-accent/30" />
            </div>
          </div>
          <label className="flex items-center gap-2 px-3 py-2 text-xs font-semibold text-ink border-b border-line cursor-pointer hover:bg-cream/60">
            <input type="checkbox" checked={selected.length === 0} onChange={() => onChange([])} /> All asset types
          </label>
          <div className="max-h-64 overflow-y-auto">
            {visible.map((option) => (
              <label key={option.id} className="flex items-start gap-2 px-3 py-1.5 text-xs cursor-pointer hover:bg-cream/60">
                <input type="checkbox" className="mt-0.5" checked={chosen.has(String(option.id))} onChange={() => toggle(String(option.id))} />
                <span className="min-w-0">
                  <span className="block text-ink">{option.name}</span>
                  {option.departments.length > 0 && <span className="block text-[10px] text-muted truncate">{option.departments.map((d) => d.name).join(', ')}</span>}
                </span>
              </label>
            ))}
            {visible.length === 0 && <p className="px-3 py-4 text-xs text-muted text-center">No asset type matches “{search}”.</p>}
          </div>
          <div className="flex items-center justify-between px-3 py-2 border-t border-line text-[11px]">
            <span className="text-muted">{selected.length ? `${selected.length} selected` : 'Showing every asset type'}</span>
            <button type="button" onClick={() => setOpen(false)} className="font-semibold text-accent cursor-pointer">Done</button>
          </div>
        </div>
      )}
    </div>
  );
}

/** Survey count for every enlisted asset with its department, downloadable as Excel. */
function AssetStatistics({ stats, onDownload, downloading }: {
  stats: AssetSurveyReport['asset_stats']; onDownload: () => void; downloading: boolean;
}) {
  const [search, setSearch] = useState('');
  const [onlyWithSurveys, setOnlyWithSurveys] = useState(false);

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return stats.rows.filter((r: AssetStatRow) =>
      (!onlyWithSurveys || r.total > 0)
      && (!needle || r.asset_type.toLowerCase().includes(needle) || r.department.toLowerCase().includes(needle)));
  }, [stats.rows, search, onlyWithSurveys]);

  const withSurveys = stats.rows.filter((r) => r.total > 0).length;
  const t = stats.totals;
  const cell = 'py-2 pr-4 text-right tabular-nums';

  return (
    <Card title="Asset statistics - every enlisted asset">
      <div className="flex flex-wrap items-center gap-3 mb-3">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted" />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search department or asset"
            className="w-full text-xs border border-line rounded-lg pl-9 pr-3 py-2 bg-white outline-none focus:ring-2 focus:ring-accent/30" />
        </div>
        <label className="flex items-center gap-2 text-xs text-ink cursor-pointer">
          <input type="checkbox" checked={onlyWithSurveys} onChange={(e) => setOnlyWithSurveys(e.target.checked)} /> Only assets with surveys
        </label>
        <span className="text-[11px] text-muted">{stats.rows.length} enlisted · {withSurveys} with surveys</span>
        <button type="button" onClick={onDownload} disabled={downloading || stats.rows.length === 0}
          className="flex items-center gap-1.5 bg-accent hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer disabled:cursor-not-allowed">
          <Download className="w-3.5 h-3.5" /> {downloading ? 'Preparing Excel…' : 'Download statistics (Excel)'}
        </button>
      </div>

      <div className="overflow-auto max-h-[28rem] border border-line rounded-lg">
        <table className="w-full text-left text-xs">
          <thead className="sticky top-0 bg-cream text-[10px] uppercase tracking-wide text-muted">
            <tr>
              <th className="py-2 px-3 w-12">S.No.</th><th className="py-2 pr-4">Department</th><th className="py-2 pr-4">Asset type</th>
              <th className="py-2 pr-4 text-right">Total</th><th className="py-2 pr-4 text-right">Good</th><th className="py-2 pr-4 text-right">Fair</th>
              <th className="py-2 pr-4 text-right">Poor</th><th className="py-2 pr-4 text-right">Damaged</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {rows.map((r, i) => (
              <tr key={`${r.department_id}:${r.asset_type_id}`} className={r.total === 0 ? 'text-muted' : ''}>
                <td className="py-2 px-3 text-muted">{i + 1}</td>
                <td className="py-2 pr-4">{r.department}{!r.department_active && <span title="This department is not active, but it has surveys" className="ml-1.5 text-[10px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">inactive</span>}</td>
                <td className="py-2 pr-4 font-medium text-ink">{r.asset_type}</td>
                <td className={`${cell} font-semibold`}>{num(r.total)}</td>
                <td className={cell}>{num(r.good)}</td><td className={cell}>{num(r.fair)}</td>
                <td className={cell}>{num(r.poor)}</td><td className={cell}>{num(r.damaged)}</td>
              </tr>
            ))}
            {rows.length === 0 && <tr><td colSpan={8} className="py-6 text-center text-muted">No assets match.</td></tr>}
          </tbody>
          {stats.rows.length > 0 && (
            <tfoot className="sticky bottom-0 bg-cream font-semibold text-ink">
              <tr>
                <td className="py-2 px-3" /><td className="py-2 pr-4">Total</td><td className="py-2 pr-4">{stats.rows.length} asset types</td>
                <td className={cell}>{num(t.total)}</td><td className={cell}>{num(t.good)}</td><td className={cell}>{num(t.fair)}</td>
                <td className={cell}>{num(t.poor)}</td><td className={cell}>{num(t.damaged)}</td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </Card>
  );
}
