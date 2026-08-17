import { useEffect, useMemo, useState } from 'react';
import { Search, Plus, ExternalLink, ShieldCheck, Check, X, Trash2, ChevronLeft, ChevronRight, Eye, RefreshCw } from 'lucide-react';
import * as api from '../services/api';
import type { AdminUser, Complaint, ComplaintStatus, Department, District, Tehsil, TimelineEntry, Village } from '../types';

const REGISTRATION_BADGE: Record<string, string> = {
  pending_email: 'bg-accent/10 text-accent-dark border-accent/25',
  email_verified: 'bg-blue-50 text-blue-700 border-blue-200',
  pending_review: 'bg-amber-50 text-amber-800 border-amber-200',
  active: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  unapproved: 'bg-slate-100 text-slate-600 border-slate-200',
  rejected: 'bg-status-rejected/10 text-status-rejected border-status-rejected/25',
};

const REGISTRATION_LABEL: Record<string, string> = {
  pending_email: 'Pending Email',
  email_verified: 'Email Verified',
  pending_review: 'Pending Approval',
  active: 'Approved',
  unapproved: 'Unapproved',
  rejected: 'Rejected',
};

function RegistrationBadge({ status }: { status: string }) {
  return (
    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${REGISTRATION_BADGE[status] || 'bg-line text-muted border-line'}`}>
      {REGISTRATION_LABEL[status] || status}
    </span>
  );
}

interface SurveyorsPageProps {
  onNavigateToComplaint: (id: number) => void;
}

const SURVEYING_STATUSES: ComplaintStatus[] = ['Acknowledged', 'Surveyed', 'In_Progress'];
const RESOLVED_STATUSES: ComplaintStatus[] = ['Resolved', 'Closed'];
const PAGE_SIZE = 10;

function nextStage(status: ComplaintStatus): 'Before' | 'During' | 'After' | null {
  if (status === 'Acknowledged') return 'Before';
  if (status === 'Surveyed') return 'During';
  if (status === 'In_Progress') return 'After';
  return null;
}

function initials(name: string) {
  return name.split(' ').filter(Boolean).slice(0, 2).map((n) => n[0]!.toUpperCase()).join('') || '?';
}

// Seed data appends a trailing code to some village names, e.g.
// "Abdulagarh (247)" / "Bhatla(113)" / "Sadalpur (20F)" - strip it for display only.
// Only strips parens containing a digit, so a genuine descriptive suffix like
// "Village (North)" is left alone.
function villageDisplayName(name: string): string {
  return name.replace(/\s*\([^()]*\d[^()]*\)\s*$/, '').trim();
}

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const hours = ms / 36e5;
  if (hours < 1) return `${Math.max(1, Math.round(ms / 6e4))}m`;
  if (hours < 24) return `${Math.round(hours)}h`;
  return `${Math.round(hours / 24)}d`;
}

function hoursBetween(a: string, b: string): number {
  return (new Date(b).getTime() - new Date(a).getTime()) / 36e5;
}

// Average turnaround = hours from the complaint's first "Acknowledged" event
// to its first "Resolved" event, averaged across a surveyor's resolved work.
// Takes the resolved timeline array directly (not the complaint) because the
// list endpoint this page's `complaints` come from omits `timeline` for
// performance - callers must resolve it via `timelineFor` first.
function turnaroundHours(timeline: TimelineEntry[]): number | null {
  const ack = timeline.find((t) => t.status === 'Acknowledged' && t.created_at);
  const resolved = timeline.find((t) => t.status === 'Resolved' && t.created_at);
  if (!ack?.created_at || !resolved?.created_at) return null;
  const h = hoursBetween(ack.created_at, resolved.created_at);
  return h >= 0 ? h : null;
}

type StepState = 'done' | 'current' | 'pending';

function stepStates(c: Complaint): { assigned: StepState; survey: StepState; reportSubmitted: StepState; verified: StepState } {
  const surveying = SURVEYING_STATUSES.includes(c.status);
  const resolved = RESOLVED_STATUSES.includes(c.status);
  const verified = !!c.verified_at;
  return {
    assigned: 'done',
    survey: surveying ? 'current' : 'done',
    reportSubmitted: resolved ? 'done' : 'pending',
    verified: verified ? 'done' : resolved ? 'current' : 'pending',
  };
}

const STEP_DOT: Record<StepState, string> = {
  done: 'bg-status-closed border-status-closed text-white',
  current: 'bg-accent border-accent text-white',
  pending: 'bg-white border-line text-muted',
};

function Stepper({ c }: { c: Complaint }) {
  const s = stepStates(c);
  const stage = nextStage(c.status);
  const steps: { key: string; state: StepState; label: string }[] = [
    { key: 'assigned', state: s.assigned, label: 'Assigned' },
    { key: 'survey', state: s.survey, label: s.survey === 'current' && stage ? `${stage} Stage` : 'Field Survey' },
    { key: 'report', state: s.reportSubmitted, label: 'Report Submitted' },
    { key: 'verified', state: s.verified, label: 'Verified' },
  ];
  return (
    <div className="flex items-center px-1 py-1">
      {steps.map((step, i) => (
        <div key={step.key} className="flex flex-col items-center flex-1 relative">
          <div className={`absolute top-[11px] h-0.5 bg-line ${i === 0 ? 'left-1/2 right-0' : i === steps.length - 1 ? 'left-0 right-1/2' : 'left-0 right-0'} ${step.state !== 'pending' && i > 0 ? 'bg-status-closed' : ''}`} />
          <div className={`w-[22px] h-[22px] rounded-full border-2 flex items-center justify-center text-[11px] font-bold z-10 ${STEP_DOT[step.state]}`}>
            {step.state === 'done' ? '✓' : i + 1}
          </div>
          <div className={`text-[10.5px] mt-1.5 text-center max-w-[80px] ${step.state === 'pending' ? 'text-muted' : 'text-ink font-medium'}`}>
            {step.label}
          </div>
        </div>
      ))}
    </div>
  );
}

export default function SurveyorsPage({ onNavigateToComplaint }: SurveyorsPageProps) {
  const [surveyors, setSurveyors] = useState<AdminUser[]>([]);
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const [showAssign, setShowAssign] = useState(false);
  const [assignComplaintId, setAssignComplaintId] = useState('');
  const [isAssigning, setIsAssigning] = useState(false);
  const [assignError, setAssignError] = useState('');

  const [verifyingId, setVerifyingId] = useState<number | null>(null);

  const [isApproving, setIsApproving] = useState(false);
  const [isUnapproving, setIsUnapproving] = useState(false);
  const [showReject, setShowReject] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [isRejecting, setIsRejecting] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [statusFilter, setStatusFilter] = useState<'all' | 'pending_review' | 'pending_email' | 'active' | 'unapproved' | 'rejected'>('all');

  const [editDepartmentIds, setEditDepartmentIds] = useState<number[]>([]);
  const [isSavingDepartments, setIsSavingDepartments] = useState(false);
  const [showDeptSavedPopup, setShowDeptSavedPopup] = useState(false);

  const [villages, setVillages] = useState<Village[]>([]);
  const [districts, setDistricts] = useState<District[]>([]);
  const [tehsils, setTehsils] = useState<Tehsil[]>([]);
  const [editVillageIds, setEditVillageIds] = useState<number[]>([]);
  const [villageDistrictFilter, setVillageDistrictFilter] = useState<number | ''>('');
  const [villageTehsilFilter, setVillageTehsilFilter] = useState<number | ''>('');
  const [isSavingVillages, setIsSavingVillages] = useState(false);
  const [showVillageSavedPopup, setShowVillageSavedPopup] = useState(false);
  const [villageMasterLoaded, setVillageMasterLoaded] = useState(false);
  const [isLoadingVillageMaster, setIsLoadingVillageMaster] = useState(false);

  // The list endpoint `complaints` comes from omits `timeline` for
  // performance (see ComplaintController::LIST_WITH) - backfilled per
  // complaint, on demand, only for whichever surveyor's modal is open.
  const [timelineByComplaintId, setTimelineByComplaintId] = useState<Record<number, TimelineEntry[]>>({});

  const load = async () => {
    setIsLoading(true);
    try {
      const [{ users }, { complaints }, deptRes] = await Promise.all([
        api.getUsers(),
        api.getComplaints(),
        api.masterApi('departments').list(),
      ]);
      const engineers = users.filter((u) => u.role === 'engineer');
      setSurveyors(engineers);
      setComplaints(complaints);
      setDepartments(deptRes.items || []);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  // Villages is a large master list (thousands of rows) only needed once the
  // admin opens a surveyor's modal - loading it eagerly on page load would
  // block the whole Surveyors table behind a multi-second request.
  useEffect(() => {
    if (!selectedId || villageMasterLoaded || isLoadingVillageMaster) return;
    setIsLoadingVillageMaster(true);
    Promise.all([
      api.masterApi('villages').list(),
      api.masterApi('districts').list(),
      api.masterApi('tehsils').list(),
    ])
      .then(([villageRes, districtRes, tehsilRes]) => {
        setVillages(villageRes.items || []);
        setDistricts(districtRes.items || []);
        setTehsils(tehsilRes.items || []);
        setVillageMasterLoaded(true);
      })
      .catch((err) => setError((err as Error).message))
      .finally(() => setIsLoadingVillageMaster(false));
  }, [selectedId, villageMasterLoaded, isLoadingVillageMaster]);

  useEffect(() => {
    setPage(1);
  }, [search, statusFilter]);

  const tasksFor = (surveyorId: number) => complaints.filter((c) => c.assigned_to_id === surveyorId);

  const timelineFor = (c: Complaint): TimelineEntry[] => c.timeline ?? timelineByComplaintId[c.id] ?? [];

  // Fetch full detail (with timeline) for whichever surveyor's modal is open,
  // for just their tasks - not the whole complaints list, which is what made
  // the list endpoint drop `timeline` in the first place.
  useEffect(() => {
    if (!selectedId) return;
    const missingIds = tasksFor(selectedId)
      .filter((c) => c.timeline === undefined && timelineByComplaintId[c.id] === undefined)
      .map((c) => c.id);
    if (missingIds.length === 0) return;

    Promise.all(missingIds.map((id) => api.getComplaint(id).then(({ complaint }) => [id, complaint.timeline ?? []] as const)))
      .then((entries) => {
        setTimelineByComplaintId((prev) => ({ ...prev, ...Object.fromEntries(entries) }));
      })
      .catch(() => {
        // Best-effort - turnaround/timestamps just stay blank for these tasks
        // rather than blocking the rest of the modal.
      });
  }, [selectedId, complaints]); // eslint-disable-line react-hooks/exhaustive-deps

  const filteredSurveyors = useMemo(() => {
    const q = search.trim().toLowerCase();
    return surveyors.filter((s) => {
      const status = s.registration_status || 'active';
      if (statusFilter !== 'all' && status !== statusFilter) return false;
      if (!q) return true;
      return [
        s.name,
        s.username,
        s.email,
        s.employee_id,
        s.district?.name,
        s.department?.name,
        ...(s.departments || []).map((d) => d.name),
        ...(s.villages || []).map((v) => v.name),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(q);
    });
  }, [surveyors, search, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredSurveyors.length / PAGE_SIZE));
  const paginated = filteredSurveyors.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const selected = surveyors.find((s) => s.id === selectedId) ?? null;
  const selectedTasks = selected ? tasksFor(selected.id) : [];
  const activeTasks = selectedTasks.filter((c) => SURVEYING_STATUSES.includes(c.status));
  const resolvedTasks = selectedTasks.filter((c) => RESOLVED_STATUSES.includes(c.status));
  const assignedTasks = selectedTasks
    .filter((c) => !c.verified_at && c.status !== 'Rejected')
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  const completedTasks = selectedTasks
    .filter((c) => !!c.verified_at)
    .sort((a, b) => new Date(b.verified_at!).getTime() - new Date(a.verified_at!).getTime());
  const turnarounds = resolvedTasks.map((c) => turnaroundHours(timelineFor(c))).filter((h): h is number => h !== null);
  const avgTurnaround = turnarounds.length ? Math.round(turnarounds.reduce((a, b) => a + b, 0) / turnarounds.length) : null;

  // Open complaints not already assigned to the selected surveyor - candidates
  // for the "Assign Complaint" action (reuses the existing transfer endpoint).
  // Complaints in one of the surveyor's assigned villages are surfaced first
  // (not hidden) since that's their coverage area.
  const assignedVillageIds = new Set((selected?.villages || []).map((v) => v.id));
  const assignableComplaints = complaints
    .filter((c) => !['Closed', 'Rejected'].includes(c.status) && c.assigned_to_id !== selected?.id)
    .sort((a, b) => {
      const aMatch = a.village_id !== null && assignedVillageIds.has(a.village_id) ? 1 : 0;
      const bMatch = b.village_id !== null && assignedVillageIds.has(b.village_id) ? 1 : 0;
      return bMatch - aMatch;
    });

  const closeModal = () => {
    setSelectedId(null);
    setShowAssign(false);
    setShowReject(false);
    setRejectReason('');
    setAssignComplaintId('');
    setAssignError('');
    setDeleteTarget(null);
    setEditDepartmentIds([]);
    setShowDeptSavedPopup(false);
    setEditVillageIds([]);
    setVillageDistrictFilter('');
    setVillageTehsilFilter('');
    setShowVillageSavedPopup(false);
  };

  useEffect(() => {
    if (!selected) {
      setEditDepartmentIds([]);
      setEditVillageIds([]);
      return;
    }
    const ids =
      selected.departments && selected.departments.length > 0
        ? selected.departments.map((d) => d.id)
        : selected.department_id
          ? [selected.department_id]
          : [];
    setEditDepartmentIds(ids);
    setEditVillageIds((selected.villages || []).map((v) => v.id));
    setVillageDistrictFilter(selected.district_id ?? '');
    setVillageTehsilFilter('');
  }, [selectedId]); // eslint-disable-line react-hooks/exhaustive-deps

  const toggleDepartment = (id: number) => {
    setEditDepartmentIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const handleSaveDepartments = async () => {
    if (!selected) return;
    setIsSavingDepartments(true);
    setError('');
    try {
      const { user } = await api.updateUser(selected.id, { department_ids: editDepartmentIds });
      setSurveyors((prev) => prev.map((s) => (s.id === selected.id ? { ...s, ...user } : s)));
      setShowDeptSavedPopup(true);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSavingDepartments(false);
    }
  };

  const toggleVillage = (id: number) => {
    setEditVillageIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const handleSaveVillages = async () => {
    if (!selected) return;
    setIsSavingVillages(true);
    setError('');
    try {
      const { user } = await api.updateUser(selected.id, {
        village_ids: editVillageIds,
        district_id: villageDistrictFilter || null,
      });
      setSurveyors((prev) => prev.map((s) => (s.id === selected.id ? { ...s, ...user } : s)));
      setShowVillageSavedPopup(true);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSavingVillages(false);
    }
  };

  const filteredTehsilsForVillagePicker = villageDistrictFilter
    ? tehsils.filter((t) => t.district_id === villageDistrictFilter)
    : tehsils;

  const filteredVillagesForPicker = villages.filter((v) => {
    if (villageTehsilFilter) return v.tehsil_id === villageTehsilFilter;
    if (villageDistrictFilter) return filteredTehsilsForVillagePicker.some((t) => t.id === v.tehsil_id);
    return true;
  });

  const handleAssign = async () => {
    if (!selected || !assignComplaintId) return;
    setIsAssigning(true);
    setAssignError('');
    try {
      const { complaint } = await api.transferComplaint(Number(assignComplaintId), selected.id);
      setComplaints((prev) => prev.map((c) => (c.id === complaint.id ? complaint : c)));
      setShowAssign(false);
      setAssignComplaintId('');
    } catch (err) {
      setAssignError((err as Error).message);
    } finally {
      setIsAssigning(false);
    }
  };

  const handleVerify = async (c: Complaint) => {
    setVerifyingId(c.id);
    setError('');
    try {
      const { complaint } = await api.verifyComplaint(c.id);
      setComplaints((prev) => prev.map((x) => (x.id === complaint.id ? complaint : x)));
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setVerifyingId(null);
    }
  };

  const handleApprove = async () => {
    if (!selected) return;
    setIsApproving(true);
    setError('');
    try {
      await api.approveRegistration(selected.id);
      setSurveyors((prev) =>
        prev.map((s) =>
          s.id === selected.id
            ? { ...s, registration_status: 'active', is_active: true, rejection_reason: null }
            : s,
        ),
      );
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsApproving(false);
    }
  };

  const handleUnapprove = async () => {
    if (!selected) return;
    setIsUnapproving(true);
    setError('');
    try {
      await api.unapproveRegistration(selected.id, 'Unapproved by admin');
      setSurveyors((prev) =>
        prev.map((s) =>
          s.id === selected.id
            ? { ...s, registration_status: 'unapproved', is_active: false, rejection_reason: 'Unapproved by admin' }
            : s,
        ),
      );
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsUnapproving(false);
    }
  };

  const handleReject = async () => {
    if (!selected || !rejectReason.trim()) return;
    setIsRejecting(true);
    setError('');
    try {
      await api.rejectRegistration(selected.id, rejectReason.trim());
      setSurveyors((prev) =>
        prev.map((s) =>
          s.id === selected.id
            ? { ...s, registration_status: 'rejected', is_active: false, rejection_reason: rejectReason.trim() }
            : s,
        ),
      );
      setShowReject(false);
      setRejectReason('');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsRejecting(false);
    }
  };

  const confirmDelete = async () => {
    if (!deleteTarget) return;
    const targetId = deleteTarget.id;
    setIsDeleting(true);
    setError('');
    try {
      await api.deleteUser(targetId);
      setSurveyors((prev) => prev.filter((s) => s.id !== targetId));
      setDeleteTarget(null);
      if (selectedId === targetId) closeModal();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsDeleting(false);
    }
  };

  if (isLoading) return <p className="text-sm text-muted">Loading…</p>;

  return (
    <div className="h-full flex flex-col">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2 mb-3">{error}</p>}

      <div className="flex items-center gap-2 mb-3">
        <div className="relative max-w-sm flex-1">
          <Search className="w-3.5 h-3.5 text-muted absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search surveyor or department…"
            className="w-full text-xs border border-line rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <button
          type="button"
          onClick={load}
          title="Refresh"
          disabled={isLoading}
          className="inline-flex items-center gap-1.5 text-ink border border-line bg-white hover:bg-cream text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      <div className="flex flex-wrap gap-1.5 mb-3">
        {(
          [
            ['all', 'All'],
            ['pending_review', 'Pending Approval'],
            ['pending_email', 'Pending Email'],
            ['active', 'Approved'],
            ['unapproved', 'Unapproved'],
            ['rejected', 'Rejected'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            onClick={() => setStatusFilter(value)}
            className={`text-[11px] font-bold px-2.5 py-1 rounded-full border cursor-pointer ${
              statusFilter === value
                ? 'bg-sidebar text-white border-sidebar'
                : 'bg-white text-muted border-line hover:border-sidebar/40'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {paginated.length === 0 ? (
          <p className="text-sm text-muted p-6 text-center">No surveyors found.</p>
        ) : (
          <table className="w-full text-xs border-separate border-spacing-0">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-3 font-bold w-12">S.No</th>
                <th className="text-left p-3 font-bold">Surveyor</th>
                <th className="text-left p-3 font-bold">Emp ID / Code</th>
                <th className="text-left p-3 font-bold">District</th>
                <th className="text-left p-3 font-bold">Departments</th>
                <th className="text-left p-3 font-bold">Villages</th>
                <th className="text-left p-3 font-bold">Status</th>
                <th className="text-left p-3 font-bold">Active</th>
                <th className="text-left p-3 font-bold">Completed</th>
                <th className="text-left p-3 font-bold">Joined</th>
                <th className="text-center p-3 font-bold w-16">Action</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((s, idx) => {
                const active = tasksFor(s.id).filter((c) => SURVEYING_STATUSES.includes(c.status)).length;
                const completed = tasksFor(s.id).filter((c) => RESOLVED_STATUSES.includes(c.status)).length;
                const deptNames =
                  s.departments && s.departments.length > 0
                    ? s.departments.map((d) => d.name).join(', ')
                    : s.department?.name || '—';
                const villageNames = s.villages && s.villages.length > 0 ? s.villages.map((v) => villageDisplayName(v.name)).join(', ') : '—';
                const serialNo = (page - 1) * PAGE_SIZE + idx + 1;
                return (
                  <tr
                    key={s.id}
                    onClick={() => setSelectedId(s.id)}
                    className={`border-t border-slate-100 cursor-pointer transition-colors hover:bg-accent/5 ${idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'}`}
                  >
                    <td className="p-3 text-slate-500 font-medium">{serialNo}</td>
                    <td className="p-3">
                      <div className="flex items-center gap-2.5">
                        <span className="w-8 h-8 rounded-full bg-sidebar text-white font-serif font-semibold text-[12px] flex items-center justify-center shrink-0">
                          {initials(s.name || s.username)}
                        </span>
                        <div className="min-w-0">
                          <p className="font-semibold text-ink truncate">{s.name || s.username}</p>
                          <p className="text-[11px] text-muted truncate">{s.mobile || s.username}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-3">
                      <span className="font-mono text-[11.5px] font-semibold text-ink">
                        {s.employee_id || '—'}
                      </span>
                    </td>
                    <td className="p-3 text-slate-700">{s.district?.name || '—'}</td>
                    <td className="p-3 text-slate-700 max-w-[160px]">
                      <span className="line-clamp-2" title={deptNames}>{deptNames}</span>
                    </td>
                    <td className="p-3 text-slate-700 max-w-[160px]">
                      <span className="line-clamp-2" title={villageNames}>{villageNames}</span>
                    </td>
                    <td className="p-3">
                      {s.registration_status ? <RegistrationBadge status={s.registration_status} /> : <RegistrationBadge status="active" />}
                    </td>
                    <td className="p-3">
                      <span className="flex items-center gap-1.5 text-slate-700">
                        <span className="w-1.5 h-1.5 rounded-full bg-status-progress shrink-0" />
                        {active}
                      </span>
                    </td>
                    <td className="p-3">
                      <span className="flex items-center gap-1.5 text-slate-700">
                        <span className="w-1.5 h-1.5 rounded-full bg-status-closed shrink-0" />
                        {completed}
                      </span>
                    </td>
                    <td className="p-3 text-slate-500 whitespace-nowrap">
                      {new Date(s.created_at).toLocaleDateString(undefined, {
                        day: '2-digit',
                        month: 'short',
                        year: 'numeric',
                      })}
                    </td>
                    <td className="p-3 text-center">
                      <div className="inline-flex items-center gap-1.5">
                        <button
                          type="button"
                          title="View surveyor"
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedId(s.id);
                          }}
                          className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-sidebar hover:bg-sidebar hover:text-white hover:border-sidebar cursor-pointer transition-colors"
                        >
                          <Eye className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          title="Delete surveyor"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDeleteTarget(s);
                          }}
                          className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-muted hover:bg-status-rejected hover:text-white hover:border-status-rejected cursor-pointer transition-colors"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}

        {filteredSurveyors.length > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>
              Showing {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filteredSurveyors.length)} of {filteredSurveyors.length}
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page === 1}
                className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={page === totalPages}
                className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer"
              >
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Detail modal */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-6" onClick={closeModal}>
          <div
            className="bg-white rounded-2xl w-full max-w-3xl max-h-[85vh] overflow-y-auto p-6 relative"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={closeModal}
              className="absolute top-4 right-4 text-muted hover:text-ink cursor-pointer"
              aria-label="Close"
            >
              <X className="w-4.5 h-4.5" />
            </button>

            <div className="flex items-center gap-4 mb-6 flex-wrap">
              <span className="w-14 h-14 rounded-full bg-sidebar text-white font-serif font-semibold text-lg flex items-center justify-center shrink-0">
                {initials(selected.name || selected.username)}
              </span>
              <div>
                <div className="flex items-center gap-2">
                  <p className="font-serif font-semibold text-[19px] text-ink">{selected.name || selected.username}</p>
                  {selected.registration_status && selected.registration_status !== 'active' && (
                    <RegistrationBadge status={selected.registration_status} />
                  )}
                  {selected.registration_status === 'active' && <RegistrationBadge status="active" />}
                </div>
                <p className="text-[12.5px] text-muted">
                  {[
                    selected.employee_id,
                    selected.district?.name,
                    selected.mobile || selected.username,
                    `Joined ${new Date(selected.created_at).toLocaleDateString(undefined, {
                      day: '2-digit',
                      month: 'short',
                      year: 'numeric',
                    })}`,
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
                {selected.registration_status === 'rejected' && selected.rejection_reason && (
                  <p className="text-[11.5px] text-status-rejected mt-0.5">Rejected: {selected.rejection_reason}</p>
                )}
              </div>
              <div className="flex gap-5 ml-auto">
                <div className="text-center">
                  <p className="font-serif font-semibold text-xl text-ink">{activeTasks.length}</p>
                  <p className="text-[10.5px] text-muted uppercase tracking-wide">Active</p>
                </div>
                <div className="text-center">
                  <p className="font-serif font-semibold text-xl text-ink">{resolvedTasks.length}</p>
                  <p className="text-[10.5px] text-muted uppercase tracking-wide">Completed</p>
                </div>
                <div className="text-center">
                  <p className="font-serif font-semibold text-xl text-ink">{avgTurnaround !== null ? `${avgTurnaround}h` : '—'}</p>
                  <p className="text-[10.5px] text-muted uppercase tracking-wide">Avg. Turnaround</p>
                </div>
              </div>
            </div>

            {showDeptSavedPopup && (
              <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/40 p-4" onClick={() => setShowDeptSavedPopup(false)}>
                <div
                  className="bg-white rounded-2xl shadow-xl w-full max-w-sm p-5 text-center"
                  onClick={(e) => e.stopPropagation()}
                >
                  <div className="mx-auto mb-3 w-12 h-12 rounded-full bg-status-closed/15 text-status-closed flex items-center justify-center">
                    <Check className="w-6 h-6" />
                  </div>
                  <p className="font-serif font-semibold text-lg text-ink mb-1">Departments saved</p>
                  <p className="text-sm text-muted mb-4">
                    {editDepartmentIds.length === 0
                      ? 'All departments cleared for this surveyor.'
                      : `${editDepartmentIds.length} department${editDepartmentIds.length > 1 ? 's' : ''} assigned successfully.`}
                  </p>
                  <button
                    type="button"
                    onClick={() => setShowDeptSavedPopup(false)}
                    className="bg-sidebar hover:opacity-90 text-white text-xs font-bold px-4 py-2 rounded-lg cursor-pointer"
                  >
                    OK
                  </button>
                </div>
              </div>
            )}

            <div className="mb-6 border border-line rounded-xl p-4 bg-cream/40">
              <div className="flex items-center justify-between gap-2 mb-2">
                <p className="text-[11px] tracking-wide uppercase text-muted font-semibold">Survey Departments</p>
                <button
                  type="button"
                  disabled={isSavingDepartments}
                  onClick={handleSaveDepartments}
                  className="text-[11px] font-bold px-2.5 py-1 rounded-lg bg-sidebar text-white disabled:opacity-50 cursor-pointer"
                >
                  {isSavingDepartments ? 'Saving…' : 'Save departments'}
                </button>
              </div>
              <p className="text-[11.5px] text-muted mb-2">
                Assign departments this surveyor can work on. In the mobile app they first pick a department, then only that department&apos;s assets appear.
              </p>
              {departments.length === 0 ? (
                <p className="text-xs text-muted">No departments in master data yet.</p>
              ) : (
                <div className="flex flex-wrap gap-1.5">
                  {departments.map((d) => {
                    const on = editDepartmentIds.includes(d.id);
                    return (
                      <button
                        key={d.id}
                        type="button"
                        onClick={() => toggleDepartment(d.id)}
                        className={`text-[11px] font-semibold px-2.5 py-1 rounded-full border cursor-pointer ${
                          on
                            ? 'bg-sidebar text-white border-sidebar'
                            : 'bg-white text-muted border-line hover:border-sidebar/40'
                        }`}
                      >
                        {d.name}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>

            {showVillageSavedPopup && (
              <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/40 p-4" onClick={() => setShowVillageSavedPopup(false)}>
                <div
                  className="bg-white rounded-2xl shadow-xl w-full max-w-sm p-5 text-center"
                  onClick={(e) => e.stopPropagation()}
                >
                  <div className="mx-auto mb-3 w-12 h-12 rounded-full bg-status-closed/15 text-status-closed flex items-center justify-center">
                    <Check className="w-6 h-6" />
                  </div>
                  <p className="font-serif font-semibold text-lg text-ink mb-1">Villages saved</p>
                  <p className="text-sm text-muted mb-4">
                    {editVillageIds.length === 0
                      ? 'All villages cleared for this surveyor.'
                      : `${editVillageIds.length} village${editVillageIds.length > 1 ? 's' : ''} assigned successfully.`}
                  </p>
                  <button
                    type="button"
                    onClick={() => setShowVillageSavedPopup(false)}
                    className="bg-sidebar hover:opacity-90 text-white text-xs font-bold px-4 py-2 rounded-lg cursor-pointer"
                  >
                    OK
                  </button>
                </div>
              </div>
            )}

            <div className="mb-6 border border-line rounded-xl p-4 bg-cream/40">
              <div className="flex items-center justify-between gap-2 mb-2">
                <p className="text-[11px] tracking-wide uppercase text-muted font-semibold">Survey Villages</p>
                <button
                  type="button"
                  disabled={isSavingVillages || !villageMasterLoaded}
                  onClick={handleSaveVillages}
                  className="text-[11px] font-bold px-2.5 py-1 rounded-lg bg-sidebar text-white disabled:opacity-50 cursor-pointer"
                >
                  {isSavingVillages ? 'Saving…' : 'Save villages'}
                </button>
              </div>
              <p className="text-[11.5px] text-muted mb-2">
                Assign the district/tehsil/village(s) this surveyor is responsible for. This is for tracking coverage only — it does not restrict what they can survey in the mobile app.
              </p>
              {!villageMasterLoaded ? (
                <p className="text-xs text-muted">Loading villages…</p>
              ) : (
                <>
                  <div className="flex flex-wrap gap-3 mb-2.5">
                    <label className="flex flex-col gap-1">
                      <span className="text-[10px] uppercase tracking-wide text-muted font-semibold">District</span>
                      <select
                        value={villageDistrictFilter}
                        onChange={(e) => {
                          setVillageDistrictFilter(e.target.value ? Number(e.target.value) : '');
                          setVillageTehsilFilter('');
                        }}
                        className="text-xs border border-line rounded-lg px-2.5 py-1.5 bg-white"
                      >
                        <option value="">Select district…</option>
                        {districts.map((d) => (
                          <option key={d.id} value={d.id}>{d.name}</option>
                        ))}
                      </select>
                    </label>
                    <label className="flex flex-col gap-1">
                      <span className="text-[10px] uppercase tracking-wide text-muted font-semibold">Tehsil</span>
                      <select
                        value={villageTehsilFilter}
                        disabled={!villageDistrictFilter}
                        onChange={(e) => setVillageTehsilFilter(e.target.value ? Number(e.target.value) : '')}
                        className="text-xs border border-line rounded-lg px-2.5 py-1.5 bg-white disabled:opacity-50"
                      >
                        <option value="">All tehsils</option>
                        {filteredTehsilsForVillagePicker.map((t) => (
                          <option key={t.id} value={t.id}>{t.name}</option>
                        ))}
                      </select>
                    </label>
                  </div>
                  {!villageDistrictFilter ? (
                    <p className="text-xs text-muted">Select a district (then optionally a tehsil) to see its villages.</p>
                  ) : filteredVillagesForPicker.length === 0 ? (
                    <p className="text-xs text-muted">No villages match this filter.</p>
                  ) : (
                    <div className="flex flex-wrap gap-1.5 max-h-40 overflow-y-auto">
                      {filteredVillagesForPicker.map((v) => {
                        const on = editVillageIds.includes(v.id);
                        return (
                          <button
                            key={v.id}
                            type="button"
                            onClick={() => toggleVillage(v.id)}
                            className={`text-[11px] font-semibold px-2.5 py-1 rounded-full border cursor-pointer ${
                              on
                                ? 'bg-sidebar text-white border-sidebar'
                                : 'bg-white text-muted border-line hover:border-sidebar/40'
                            }`}
                          >
                            {villageDisplayName(v.name)}
                          </button>
                        );
                      })}
                    </div>
                  )}
                </>
              )}
            </div>

            <div className="flex items-center gap-2 mb-6 flex-wrap">
              {(() => {
                const status = selected.registration_status || 'active';
                const canApprove = status === 'pending_review' || status === 'unapproved' || status === 'rejected';
                const canUnapprove = status === 'active';
                const canReject =
                  status === 'pending_review' ||
                  status === 'pending_email' ||
                  status === 'email_verified' ||
                  status === 'unapproved';
                const waitingOnUser = status === 'pending_email' || status === 'email_verified';

                return (
                  <>
                    {waitingOnUser && (
                      <p className="w-full text-[11.5px] text-muted mb-1">
                        {status === 'pending_email'
                          ? 'Waiting for surveyor to verify email and set password before you can approve.'
                          : 'Email verified — waiting for surveyor to set password before you can approve.'}
                      </p>
                    )}
                    {canApprove && (
                      <button
                        disabled={isApproving}
                        onClick={handleApprove}
                        className="flex items-center gap-1.5 bg-status-closed hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                      >
                        <Check className="w-3.5 h-3.5" />
                        {isApproving ? 'Approving…' : 'Approve'}
                      </button>
                    )}
                    {canUnapprove && (
                      <button
                        disabled={isUnapproving}
                        onClick={handleUnapprove}
                        className="flex items-center gap-1.5 border border-slate-400 text-slate-700 hover:bg-slate-100 disabled:opacity-50 text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                      >
                        <ShieldCheck className="w-3.5 h-3.5" />
                        {isUnapproving ? 'Unapproving…' : 'Unapprove'}
                      </button>
                    )}
                    {canReject && (
                      <button
                        onClick={() => setShowReject((v) => !v)}
                        className="flex items-center gap-1.5 border border-status-rejected text-status-rejected hover:bg-status-rejected/10 text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                      >
                        <X className="w-3.5 h-3.5" />
                        Reject
                      </button>
                    )}
                    {status === 'active' && (
                      <button
                        onClick={() => setShowAssign((v) => !v)}
                        className="flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                      >
                        <Plus className="w-3.5 h-3.5" />
                        Assign Complaint
                      </button>
                    )}
                  </>
                );
              })()}
              <button
                disabled={isDeleting}
                onClick={() => setDeleteTarget(selected)}
                title="Delete surveyor"
                className="flex items-center justify-center border border-line hover:border-status-rejected hover:text-status-rejected hover:bg-status-rejected/5 disabled:opacity-50 text-muted p-2 rounded-lg cursor-pointer"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>

            {showReject &&
              selected.registration_status &&
              ['pending_review', 'pending_email', 'email_verified', 'unapproved'].includes(selected.registration_status) && (
              <div className="mb-6 border border-status-rejected/25 rounded-xl p-4 bg-status-rejected/5 space-y-2">
                <div className="flex gap-2">
                  <input
                    value={rejectReason}
                    onChange={(e) => setRejectReason(e.target.value)}
                    placeholder="Reason for rejection…"
                    className="flex-1 text-xs border border-line rounded-lg px-2.5 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-status-rejected"
                  />
                  <button
                    disabled={!rejectReason.trim() || isRejecting}
                    onClick={handleReject}
                    className="bg-status-rejected hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                  >
                    {isRejecting ? 'Rejecting…' : 'Confirm Reject'}
                  </button>
                </div>
              </div>
            )}

            {showAssign && (
              <div className="mb-6 border border-line rounded-xl p-4 bg-cream/50 space-y-2">
                {assignError && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{assignError}</p>}
                <div className="flex gap-2">
                  <select
                    value={assignComplaintId}
                    onChange={(e) => setAssignComplaintId(e.target.value)}
                    className="flex-1 text-xs border border-line rounded-lg px-2.5 py-2 bg-white"
                  >
                    <option value="">Select a complaint…</option>
                    {assignableComplaints.map((c) => {
                      const inAssignedVillage = c.village_id !== null && assignedVillageIds.has(c.village_id);
                      return (
                        <option key={c.id} value={c.id}>
                          {inAssignedVillage ? '★ ' : ''}{c.code ?? `CMP-${c.id}`} · {c.category?.name ?? 'Uncategorised'} · {[c.village, c.panchayat].filter(Boolean).join(', ') || 'No location'} · {c.status.replace('_', ' ')}
                          {inAssignedVillage ? ' (assigned area)' : ''}
                        </option>
                      );
                    })}
                  </select>
                  <button
                    disabled={!assignComplaintId || isAssigning}
                    onClick={handleAssign}
                    className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                  >
                    Assign
                  </button>
                </div>
              </div>
            )}

            <p className="text-[11px] tracking-wide uppercase text-muted font-semibold mb-3">Assigned Tasks</p>
            {assignedTasks.length === 0 ? (
              <p className="text-sm text-muted mb-6">No open tasks for this surveyor.</p>
            ) : (
              <div className="space-y-3.5 mb-6">
                {assignedTasks.map((c) => {
                  const s = stepStates(c);
                  const ack = timelineFor(c).find((t) => t.status === 'Acknowledged')?.created_at;
                  const resolvedAt = timelineFor(c).find((t) => t.status === 'Resolved')?.created_at;
                  return (
                    <div key={c.id} className="border border-line rounded-xl overflow-hidden">
                      <div className="flex justify-between items-center px-4 py-3.5 border-b border-line">
                        <div>
                          <p className="text-[13.5px] font-semibold text-ink">{c.category?.name ?? 'Uncategorised'}{c.village ? ` — ${c.village}` : ''}</p>
                          <p className="text-[11.5px] text-muted mt-0.5">{[c.village, c.panchayat].filter(Boolean).join(' · ') || 'No location'}</p>
                        </div>
                        <span className="font-mono text-[10.5px] text-muted border border-line px-2 py-1 rounded">{c.code ?? `CMP-${c.id}`}</span>
                      </div>
                      <Stepper c={c} />
                      <div className="flex justify-between items-center px-4 pb-3.5 text-[11.5px] text-muted">
                        <span>
                          {s.verified === 'current'
                            ? <>Resolved <b className="text-ink">{resolvedAt ? timeAgo(resolvedAt) : ''}</b> ago</>
                            : <>Assigned <b className="text-ink">{ack ? timeAgo(ack) : ''}</b> ago</>}
                        </span>
                        {s.verified === 'current' ? (
                          <button
                            disabled={verifyingId === c.id}
                            onClick={() => handleVerify(c)}
                            className="flex items-center gap-1 text-accent font-semibold cursor-pointer disabled:opacity-50"
                          >
                            <ShieldCheck className="w-3.5 h-3.5" />
                            {verifyingId === c.id ? 'Verifying…' : 'VERIFY REPORT'} →
                          </button>
                        ) : (
                          <button onClick={() => onNavigateToComplaint(c.id)} className="flex items-center gap-1 text-accent font-semibold cursor-pointer">
                            VIEW DETAILS <ExternalLink className="w-3 h-3" />
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            <p className="text-[11px] tracking-wide uppercase text-muted font-semibold mb-3">Recently Completed</p>
            {completedTasks.length === 0 ? (
              <p className="text-sm text-muted">Nothing verified yet.</p>
            ) : (
              <div className="space-y-3.5">
                {completedTasks.slice(0, 5).map((c) => (
                  <div key={c.id} className="border border-line rounded-xl overflow-hidden">
                    <div className="flex justify-between items-center px-4 py-3.5 border-b border-line">
                      <div>
                        <p className="text-[13.5px] font-semibold text-ink">{c.category?.name ?? 'Uncategorised'}{c.village ? ` — ${c.village}` : ''}</p>
                        <p className="text-[11.5px] text-muted mt-0.5">{[c.village, c.panchayat].filter(Boolean).join(' · ') || 'No location'}</p>
                      </div>
                      <span className="font-mono text-[10.5px] text-muted border border-line px-2 py-1 rounded">CMP-{c.id}</span>
                    </div>
                    <Stepper c={c} />
                    <div className="flex justify-between items-center px-4 pb-3.5 text-[11.5px] text-muted">
                      <span>Verified <b className="text-ink">{timeAgo(c.verified_at!)}</b> ago</span>
                      <button onClick={() => onNavigateToComplaint(c.id)} className="flex items-center gap-1 text-accent font-semibold cursor-pointer">
                        VIEW REPORT <ExternalLink className="w-3 h-3" />
                      </button>
                    </div>
                  </div>
                ))}
                {completedTasks.length > 5 && (
                  <p className="text-xs text-muted">Showing 5 of {completedTasks.length} completed tasks.</p>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Delete confirmation */}
      {deleteTarget && (
        <div
          className="fixed inset-0 bg-black/40 z-[60] flex items-center justify-center p-6"
          onClick={() => setDeleteTarget(null)}
        >
          <div
            className="bg-white rounded-2xl w-full max-w-sm p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <p className="font-serif font-semibold text-lg text-ink mb-2">Delete surveyor?</p>
            <p className="text-sm text-muted mb-6">
              Delete <b className="text-ink">{deleteTarget.name || deleteTarget.username}</b>? This permanently removes their account
              and all surveys/assets they submitted, and cannot be undone.
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setDeleteTarget(null)}
                className="text-xs font-bold px-3.5 py-2 rounded-lg border border-line text-muted hover:bg-slate-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                disabled={isDeleting}
                onClick={confirmDelete}
                className="flex items-center gap-1.5 bg-status-rejected hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
              >
                <Trash2 className="w-3.5 h-3.5" />
                {isDeleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
