import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Inbox, MapPin, User, UserCheck, Flag, FileText, Search, Wrench, CheckCircle2, Star, XCircle,
  RotateCcw, ArrowLeftRight, Repeat, Download, X, ChevronLeft, ChevronRight, CalendarClock,
  Navigation, Camera, ExternalLink, UserX, Building2, Landmark,
} from 'lucide-react';
import * as api from '../services/api';
import { masterApi } from '../services/api';
import type { AssignableUser, Complaint, ComplaintCategory, ComplaintStatus, User as UserType } from '../types';
import { StatusBadge, PriorityBadge, statusAccent } from '../components/StatusBadge';

interface ComplaintsPageProps {
  currentUser: UserType;
  initialStatus?: ComplaintStatus | 'All' | null;
  initialComplaintId?: number | null;
}

const TABS: (ComplaintStatus | 'All')[] = [
  'All', 'Pending', 'Acknowledged', 'Surveyed', 'In_Progress', 'Resolved', 'Rejected', 'Closed', 'Reopened',
];

const ACKNOWLEDGE_ROLES = ['sarpanch', 'secretary', 'block_admin'];
const RESOLVE_ROLES = ['department_officer', 'department_head', 'super_admin'];
const TRANSFER_ROLES = ['sarpanch', 'secretary', 'block_admin', 'department_head', 'department_officer', 'super_admin'];
const PAGE_SIZE = 10;

const TIMELINE_ICONS: Record<string, typeof FileText> = {
  Pending: FileText,
  Acknowledged: UserCheck,
  Surveyed: Search,
  In_Progress: Wrench,
  Resolved: CheckCircle2,
  Closed: Star,
  Rejected: XCircle,
  Reopened: RotateCcw,
};

// Deterministic per-category dot color (hash of the name) so each category
// reads consistently across the table without depending on fetch order.
const CATEGORY_DOT_COLORS = ['#2a78d6', '#008300', '#e87ba4', '#eda100', '#1baf7a', '#eb6834', '#4a3aa7', '#e34948'];
function categoryColor(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash);
  return CATEGORY_DOT_COLORS[Math.abs(hash) % CATEGORY_DOT_COLORS.length];
}

function toCsvValue(value: string | number | null | undefined): string {
  const s = String(value ?? '');
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function downloadCsv(rows: Complaint[]) {
  const headers = ['S.No', 'Complaint No', 'Category', 'Status', 'Priority', 'Department', 'Asset', 'Location', 'Reported By', 'Assigned To', 'Filed Date', 'Repeat Of'];
  const lines = [headers.join(',')];
  rows.forEach((c, idx) => {
    lines.push([
      idx + 1,
      c.code ?? `CMP-${c.id}`,
      c.category.name,
      c.status,
      c.priority.name,
      c.department?.name ?? '',
      c.asset_type?.name ?? '',
      [c.village, c.panchayat, c.tehsil?.name, c.district?.name].filter(Boolean).join(', '),
      c.user?.name || c.user?.username || '',
      c.assigned_to?.name || c.assigned_to?.username || '',
      new Date(c.created_at).toLocaleDateString(),
      c.duplicate_of?.code ?? (c.duplicate_of_id ?? ''),
    ].map(toCsvValue).join(','));
  });
  const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `complaints-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

export default function ComplaintsPage({ currentUser, initialStatus, initialComplaintId }: ComplaintsPageProps) {
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [categories, setCategories] = useState<ComplaintCategory[]>([]);
  const [assignableUsers, setAssignableUsers] = useState<AssignableUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<ComplaintStatus | 'All'>(initialStatus || 'All');
  const [repeatedOnly, setRepeatedOnly] = useState(false);
  const [categoryFilter, setCategoryFilter] = useState('All');
  const [searchQuery, setSearchQuery] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Complaint | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [actionError, setActionError] = useState('');

  const [assignedToId, setAssignedToId] = useState('');
  const [surveyNotes, setSurveyNotes] = useState('');
  const [resolveNotes, setResolveNotes] = useState('');
  const [rating, setRating] = useState(5);
  const [feedback, setFeedback] = useState('');
  const [transferToId, setTransferToId] = useState('');
  const [transferReason, setTransferReason] = useState('');
  const [reopenReason, setReopenReason] = useState('');
  const appliedInitialId = useRef(false);

  const load = async () => {
    setIsLoading(true);
    try {
      const { complaints } = await api.getComplaints();
      setComplaints(complaints);
      if (selected) {
        setSelected(complaints.find((c) => c.id === selected.id) || null);
      }
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
    masterApi('complaint-categories').list().then(({ items }) => setCategories(items)).catch(() => {});
    api.getAssignableUsers().then(({ users }) => setAssignableUsers(users)).catch(() => {});
  }, []);

  useEffect(() => {
    if (!appliedInitialId.current && initialComplaintId && complaints.length > 0) {
      const match = complaints.find((c) => c.id === initialComplaintId);
      if (match) {
        setSelected(match);
        appliedInitialId.current = true;
      }
    }
  }, [complaints, initialComplaintId]);

  useEffect(() => { setPage(1); }, [activeTab, repeatedOnly, categoryFilter, searchQuery]);

  const filtered = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return complaints
      .filter((c) => activeTab === 'All' || c.status === activeTab)
      .filter((c) => !repeatedOnly || c.duplicate_of_id)
      .filter((c) => categoryFilter === 'All' || c.category_id === Number(categoryFilter))
      .filter((c) => {
        if (!q) return true;
        const haystack = [
          String(c.id), c.category.name, c.description, c.village, c.panchayat,
          c.tehsil?.name, c.district?.name,
          c.department?.name, c.asset_type?.name,
          c.user?.name, c.user?.username, c.assigned_to?.name, c.assigned_to?.username,
        ].filter(Boolean).join(' ').toLowerCase();
        return haystack.includes(q);
      });
  }, [complaints, activeTab, repeatedOnly, categoryFilter, searchQuery]);

  const countFor = (tab: ComplaintStatus | 'All') => (tab === 'All' ? complaints.length : complaints.filter((c) => c.status === tab).length);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const runAction = async (fn: () => Promise<{ complaint: Complaint }>) => {
    setIsSubmitting(true);
    setActionError('');
    try {
      const { complaint } = await fn();
      setComplaints((prev) => prev.map((c) => (c.id === complaint.id ? complaint : c)));
      setSelected(complaint);
      setAssignedToId('');
      setSurveyNotes('');
      setResolveNotes('');
      setFeedback('');
      setTransferToId('');
      setTransferReason('');
      setReopenReason('');
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const nextSurveyStage = (status: ComplaintStatus): 'Before' | 'During' | 'After' | null => {
    if (status === 'Acknowledged') return 'Before';
    if (status === 'Surveyed') return 'During';
    if (status === 'In_Progress') return 'After';
    return null;
  };

  const canAcknowledge = !!selected && (selected.status === 'Pending' || selected.status === 'Reopened') && ACKNOWLEDGE_ROLES.includes(currentUser.role);
  const canSurvey = !!selected && currentUser.role === 'engineer' && !!nextSurveyStage(selected.status);
  const canResolve = !!selected && (selected.status === 'Surveyed' || selected.status === 'In_Progress') && RESOLVE_ROLES.includes(currentUser.role);
  const canRate = !!selected && selected.status === 'Resolved' && currentUser.role === 'citizen' && selected.user_id === currentUser.id;
  const canTransfer = !!selected && !['Closed', 'Rejected'].includes(selected.status) && TRANSFER_ROLES.includes(currentUser.role);
  const canReopen = !!selected && selected.status === 'Closed' && currentUser.role === 'citizen' && selected.user_id === currentUser.id;
  const isTerminal = !!selected && (selected.status === 'Rejected' || (selected.status === 'Closed' && !canReopen));
  const hasAnyAction = canAcknowledge || canSurvey || canResolve || canRate || canTransfer || canReopen || isTerminal;

  return (
    <div className="space-y-4">
      {/* Toolbar: search, category filter, repeated toggle, export */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search complaints…"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Categories</option>
          {categories.map((cat) => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
        </select>
        <button
          onClick={() => setRepeatedOnly((v) => !v)}
          className={`flex items-center gap-1 text-[11px] font-bold px-2.5 py-2 rounded-lg border transition-colors ${
            repeatedOnly ? 'bg-orange-500 text-white border-orange-500' : 'bg-white text-slate-500 border-slate-200 hover:border-slate-300'
          }`}
        >
          <Repeat className="w-3 h-3" />
          Repeated only
        </button>
        <button
          onClick={() => downloadCsv(filtered)}
          disabled={filtered.length === 0}
          className="flex items-center gap-1.5 text-xs font-bold px-3 py-2 rounded-lg border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 disabled:opacity-40 ml-auto"
        >
          <Download className="w-3.5 h-3.5" />
          Export CSV
        </button>
      </div>

      {/* Status tabs */}
      <div className="flex gap-1.5 flex-wrap">
        {TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`text-[11px] font-bold px-2.5 py-1 rounded-full border transition-colors ${
              activeTab === tab ? 'bg-accent text-white border-accent' : 'bg-white text-slate-600 border-slate-200 hover:border-slate-300'
            }`}
          >
            {tab.replace('_', ' ')}
            <span className={`ml-1.5 ${activeTab === tab ? 'text-white' : 'text-slate-400'}`}>{countFor(tab)}</span>
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        {isLoading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : filtered.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No complaints match your filters.</p>
          </div>
        ) : (
          <table className="w-full text-xs border-separate border-spacing-0">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-3 font-bold w-16">S.No.</th>
                <th className="text-left p-3 font-bold">Complaint No</th>
                <th className="text-left p-3 font-bold">Category</th>
                <th className="text-left p-3 font-bold">Department / Asset</th>
                <th className="text-left p-3 font-bold">Location</th>
                <th className="text-left p-3 font-bold">Status</th>
                <th className="text-left p-3 font-bold">Priority</th>
                <th className="text-left p-3 font-bold">Assigned To</th>
                <th className="text-left p-3 font-bold">Filed</th>
                <th className="text-left p-3 font-bold">Flags</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((c, idx) => {
                const isSelected = selected?.id === c.id;
                const assignedLabel = c.assigned_to?.name || c.assigned_to?.username;
                return (
                <tr
                  key={c.id}
                  onClick={() => setSelected(c)}
                  className={`border-t border-slate-100 cursor-pointer transition-colors hover:bg-accent/5 ${
                    isSelected ? 'bg-accent/10' : idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'
                  }`}
                >
                  <td className="p-3 font-semibold text-slate-500 tabular-nums">
                    {(page - 1) * PAGE_SIZE + idx + 1}
                  </td>
                  <td className="p-3">
                    <span className="font-mono text-[10px] font-bold text-slate-500 bg-slate-100 border border-slate-200 rounded px-1.5 py-0.5">
                      {c.code ?? `CMP-${c.id}`}
                    </span>
                  </td>
                  <td className="p-3">
                    <span className="flex items-center gap-2 font-semibold text-slate-800">
                      <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: categoryColor(c.category.name) }} />
                      {c.category.name}
                    </span>
                  </td>
                  <td className="p-3 max-w-[190px]">
                    <p className="font-semibold text-slate-700 truncate">{c.department?.name || '—'}</p>
                    <p className="text-[10px] text-slate-400 truncate">{c.asset_type?.name || '—'}</p>
                  </td>
                  <td className="p-3 text-slate-500 max-w-[160px] truncate">
                    {[c.village, c.panchayat, c.tehsil?.name, c.district?.name].filter(Boolean).join(', ') || <span className="text-slate-300 italic">No location</span>}
                  </td>
                  <td className="p-3"><StatusBadge status={c.status} /></td>
                  <td className="p-3"><PriorityBadge priority={c.priority.name} /></td>
                  <td className="p-3">
                    {assignedLabel ? (
                      <span className="flex items-center gap-1.5">
                        <span className="w-5 h-5 rounded-full bg-accent-soft text-sidebar text-[9px] font-bold flex items-center justify-center shrink-0">
                          {assignedLabel.slice(0, 2).toUpperCase()}
                        </span>
                        <span className="text-slate-600 truncate">{assignedLabel}</span>
                      </span>
                    ) : (
                      <span className="flex items-center gap-1 text-slate-300 italic">
                        <UserX className="w-3 h-3" />
                        Unassigned
                      </span>
                    )}
                  </td>
                  <td className="p-3 text-slate-400">{new Date(c.created_at).toLocaleDateString()}</td>
                  <td className="p-3">
                    {c.duplicate_of_id && (
                      <span className="flex items-center gap-0.5 text-[9px] font-bold text-orange-600 bg-orange-50 border border-orange-200 rounded-full px-1.5 py-0.5 w-fit">
                        <Repeat className="w-2.5 h-2.5" />
                        Repeat
                      </span>
                    )}
                  </td>
                </tr>
                );
              })}
            </tbody>
          </table>
        )}

        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>
              Showing {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length}
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page === 1}
                className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={page === totalPages}
                className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40"
              >
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Detail panel */}
      {selected && (
        <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
          <div className={`h-1 ${statusAccent(selected.status)}`} />
          <div className="p-5 space-y-5">
            <div className="flex items-start justify-between">
              <div>
                <h2 className="font-bold text-lg text-slate-900">{selected.category.name}</h2>
                <p className="text-xs text-slate-400 font-mono mt-0.5">{selected.code ?? `CMP-${selected.id}`}</p>
              </div>
              <div className="flex items-center gap-2">
                <StatusBadge status={selected.status} />
                <button onClick={() => setSelected(null)} className="text-slate-400 hover:text-slate-600">
                  <X className="w-4 h-4" />
                </button>
              </div>
            </div>

            {selected.duplicate_of_id && (
              <p className="flex items-center gap-1.5 text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded-lg px-3 py-2">
                <Repeat className="w-3.5 h-3.5 shrink-0" />
                Possible repeat of complaint {selected.duplicate_of?.code ?? `CMP-${selected.duplicate_of_id}`}
                {selected.duplicate_of && ` (${selected.duplicate_of.category.name})`}
              </p>
            )}

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
              {[
                { icon: User, label: 'Reported by', value: selected.user?.name || selected.user?.username || '—' },
                { icon: MapPin, label: 'Location', value: [selected.village, selected.panchayat, selected.tehsil?.name, selected.district?.name].filter(Boolean).join(', ') || '—' },
                { icon: Building2, label: 'Department', value: selected.department?.name || '—' },
                { icon: Landmark, label: 'Asset', value: selected.asset_type?.name || '—' },
                { icon: UserCheck, label: 'Assigned to', value: selected.assigned_to?.name || selected.assigned_to?.username || 'Unassigned' },
                { icon: CalendarClock, label: 'Filed', value: new Date(selected.created_at).toLocaleString() },
              ].map(({ icon: Icon, label, value }) => (
                <div key={label} className="bg-slate-50 border border-slate-100 rounded-xl p-2.5">
                  <div className="flex items-center gap-1 text-slate-400">
                    <Icon className="w-3 h-3" />
                    <span className="text-[9px] font-bold uppercase tracking-wide">{label}</span>
                  </div>
                  <p className="text-xs font-semibold text-slate-800 mt-1 truncate">{value}</p>
                </div>
              ))}
              <div className="bg-slate-50 border border-slate-100 rounded-xl p-2.5">
                <div className="flex items-center gap-1 text-slate-400">
                  <Flag className="w-3 h-3" />
                  <span className="text-[9px] font-bold uppercase tracking-wide">Priority</span>
                </div>
                <div className="mt-1"><PriorityBadge priority={selected.priority.name} /></div>
              </div>
              {selected.lat !== null && selected.long !== null && (
                <a
                  href={`https://www.google.com/maps?q=${selected.lat},${selected.long}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="bg-slate-50 border border-slate-100 rounded-xl p-2.5 hover:border-accent-soft hover:bg-accent/5 transition-colors"
                >
                  <div className="flex items-center gap-1 text-slate-400">
                    <Navigation className="w-3 h-3" />
                    <span className="text-[9px] font-bold uppercase tracking-wide">GPS Coordinates</span>
                  </div>
                  <p className="text-xs font-semibold text-accent-dark mt-1 truncate flex items-center gap-1">
                    {selected.lat!.toFixed(5)}, {selected.long!.toFixed(5)}
                    <ExternalLink className="w-2.5 h-2.5 shrink-0" />
                  </p>
                </a>
              )}
            </div>

            {selected.description && (
              <p className="text-sm text-slate-700 bg-slate-50 border-l-2 border-accent rounded-r-lg px-3.5 py-2.5">
                {selected.description}
              </p>
            )}

            {(selected.before_photo_url || selected.during_photo_url || selected.after_photo_url) && (
              <div>
                <h3 className="text-xs font-bold text-slate-500 uppercase mb-3 flex items-center gap-1.5">
                  <Camera className="w-3.5 h-3.5" />
                  Uploaded Photos
                </h3>
                <div className="grid grid-cols-3 gap-3">
                  {([
                    ['Before', selected.before_photo_url],
                    ['During', selected.during_photo_url],
                    ['After', selected.after_photo_url],
                  ] as const).filter(([, url]) => url).map(([stage, url]) => (
                    <a
                      key={stage}
                      href={api.mediaUrl(url!)}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group relative block rounded-xl overflow-hidden border border-slate-200 aspect-square"
                    >
                      <img src={api.mediaUrl(url!)} alt={`${stage} photo`} className="w-full h-full object-cover" />
                      <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center">
                        <ExternalLink className="w-4 h-4 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
                      </div>
                      <span className="absolute bottom-1 left-1.5 text-[9px] font-bold uppercase text-white bg-black/50 rounded px-1.5 py-0.5">
                        {stage}
                      </span>
                    </a>
                  ))}
                </div>
              </div>
            )}

            <div>
              <h3 className="text-xs font-bold text-slate-500 uppercase mb-3">Audit Timeline</h3>
              <ol className="relative space-y-4 before:absolute before:left-[9px] before:top-1.5 before:bottom-1.5 before:w-px before:bg-slate-200">
                {selected.timeline.map((t) => {
                  const Icon = TIMELINE_ICONS[t.status] || FileText;
                  return (
                    <li key={t.id} className="relative pl-7 text-xs">
                      <span className={`absolute left-0 top-0 w-[19px] h-[19px] rounded-full flex items-center justify-center ring-4 ring-white ${statusAccent(t.status as ComplaintStatus)}`}>
                        <Icon className="w-3 h-3 text-white" />
                      </span>
                      <span className="font-bold text-slate-800">{t.title}</span>
                      {t.description && <p className="text-slate-500 mt-0.5">{t.description}</p>}
                      <p className="text-slate-400 mt-0.5">
                        {t.performed_by?.name || t.performed_by?.username} · {t.created_at ? new Date(t.created_at).toLocaleString() : '—'}
                      </p>
                    </li>
                  );
                })}
              </ol>
            </div>

            {selected.transfers.length > 0 && (
              <div>
                <h3 className="text-xs font-bold text-slate-500 uppercase mb-3">Transfer History</h3>
                <ul className="space-y-2">
                  {selected.transfers.map((t) => (
                    <li key={t.id} className="flex items-start gap-2 text-xs bg-slate-50 border border-slate-100 rounded-lg px-3 py-2">
                      <ArrowLeftRight className="w-3.5 h-3.5 text-slate-400 mt-0.5 shrink-0" />
                      <div>
                        <p className="font-semibold text-slate-700">
                          {t.from_user?.name || t.from_user?.username || 'Unassigned'} → {t.to_user.name || t.to_user.username}
                        </p>
                        {t.reason && <p className="text-slate-500 mt-0.5">{t.reason}</p>}
                        <p className="text-slate-400 mt-0.5">
                          by {t.transferred_by.name || t.transferred_by.username} · {new Date(t.created_at).toLocaleString()}
                        </p>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {actionError && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{actionError}</p>}

            <div className="border-t border-slate-100 pt-4 space-y-3">
              <h3 className="text-xs font-bold text-slate-500 uppercase mb-2.5">Actions <span className="text-slate-300 normal-case font-semibold">({currentUser.role.replace(/_/g, ' ')})</span></h3>

              {canAcknowledge && (
                <div className="flex gap-2">
                  <select
                    value={assignedToId}
                    onChange={(e) => setAssignedToId(e.target.value)}
                    className="flex-1 text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">Assign to… (optional)</option>
                    {assignableUsers.map((u) => (
                      <option key={u.id} value={u.id}>{u.name || u.username} · {u.role.replace(/_/g, ' ')}</option>
                    ))}
                  </select>
                  <button
                    disabled={isSubmitting}
                    onClick={() => runAction(() => api.acknowledgeComplaint(selected.id, assignedToId ? Number(assignedToId) : undefined))}
                    className="bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg"
                  >
                    Acknowledge
                  </button>
                </div>
              )}

              {canSurvey && (
                <div className="space-y-2">
                  <input
                    value={surveyNotes}
                    onChange={(e) => setSurveyNotes(e.target.value)}
                    placeholder={`Notes for ${nextSurveyStage(selected.status)} stage (optional)`}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  />
                  <button
                    disabled={isSubmitting}
                    onClick={() => runAction(() => api.submitSurvey(selected.id, nextSurveyStage(selected.status)!, surveyNotes || undefined))}
                    className="bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg"
                  >
                    Submit {nextSurveyStage(selected.status)} Stage
                  </button>
                </div>
              )}

              {canResolve && (
                <div className="flex gap-2">
                  <input
                    value={resolveNotes}
                    onChange={(e) => setResolveNotes(e.target.value)}
                    placeholder="Resolution notes (optional)"
                    className="flex-1 text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  />
                  <button
                    disabled={isSubmitting}
                    onClick={() => runAction(() => api.resolveComplaint(selected.id, resolveNotes || undefined))}
                    className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg"
                  >
                    Mark Resolved
                  </button>
                </div>
              )}

              {canRate && (
                <div className="space-y-2">
                  <div className="flex items-center gap-1">
                    {[1, 2, 3, 4, 5].map((n) => (
                      <button key={n} onClick={() => setRating(n)} className={`text-lg ${n <= rating ? 'text-amber-400' : 'text-slate-200'}`}>★</button>
                    ))}
                  </div>
                  <input
                    value={feedback}
                    onChange={(e) => setFeedback(e.target.value)}
                    placeholder="Feedback (optional)"
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  />
                  <button
                    disabled={isSubmitting}
                    onClick={() => runAction(() => api.rateComplaint(selected.id, rating, feedback || undefined))}
                    className="bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg"
                  >
                    Rate & Close
                  </button>
                </div>
              )}

              {canTransfer && (
                <div className="flex gap-2">
                  <select
                    value={transferToId}
                    onChange={(e) => setTransferToId(e.target.value)}
                    className="w-48 text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">Transfer to…</option>
                    {assignableUsers.map((u) => (
                      <option key={u.id} value={u.id}>{u.name || u.username} · {u.role.replace(/_/g, ' ')}</option>
                    ))}
                  </select>
                  <input
                    value={transferReason}
                    onChange={(e) => setTransferReason(e.target.value)}
                    placeholder="Reason (optional)"
                    className="flex-1 text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  />
                  <button
                    disabled={isSubmitting || !transferToId}
                    onClick={() => runAction(() => api.transferComplaint(selected.id, Number(transferToId), transferReason || undefined))}
                    className="bg-violet-600 hover:bg-violet-700 disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg flex items-center gap-1.5"
                  >
                    <ArrowLeftRight className="w-3.5 h-3.5" />
                    Transfer
                  </button>
                </div>
              )}

              {canReopen && (
                <div className="flex gap-2">
                  <input
                    value={reopenReason}
                    onChange={(e) => setReopenReason(e.target.value)}
                    placeholder="Why are you reopening this?"
                    className="flex-1 text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  />
                  <button
                    disabled={isSubmitting || !reopenReason}
                    onClick={() => runAction(() => api.reopenComplaint(selected.id, reopenReason))}
                    className="bg-violet-600 hover:bg-violet-700 disabled:opacity-50 text-white text-xs font-bold px-3 py-1.5 rounded-lg flex items-center gap-1.5"
                  >
                    <RotateCcw className="w-3.5 h-3.5" />
                    Reopen
                  </button>
                </div>
              )}

              {isTerminal && (
                <p className="text-xs text-slate-400">No further action available — grievance is {selected.status.toLowerCase()}.</p>
              )}

              {!hasAnyAction && (
                <p className="text-xs text-slate-400">No actions available for your role at this stage.</p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
