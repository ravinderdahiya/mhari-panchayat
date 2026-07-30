import { useEffect, useMemo, useState } from 'react';
import { Search, Plus, ExternalLink, ShieldCheck, Check, X, Trash2, ChevronLeft, ChevronRight } from 'lucide-react';
import * as api from '../services/api';
import type { AdminUser, Complaint, ComplaintStatus } from '../types';

const REGISTRATION_BADGE: Record<string, string> = {
  pending_review: 'bg-accent/10 text-accent-dark border-accent/25',
  active: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  rejected: 'bg-status-rejected/10 text-status-rejected border-status-rejected/25',
};

const REGISTRATION_LABEL: Record<string, string> = {
  pending_review: 'Pending Review',
  active: 'Active',
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
function turnaroundHours(c: Complaint): number | null {
  const ack = c.timeline.find((t) => t.status === 'Acknowledged' && t.created_at);
  const resolved = c.timeline.find((t) => t.status === 'Resolved' && t.created_at);
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
  const [showReject, setShowReject] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [isRejecting, setIsRejecting] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const load = async () => {
    setIsLoading(true);
    try {
      const [{ users }, { complaints }] = await Promise.all([api.getUsers(), api.getComplaints()]);
      const engineers = users.filter((u) => u.role === 'engineer');
      setSurveyors(engineers);
      setComplaints(complaints);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    setPage(1);
  }, [search]);

  const tasksFor = (surveyorId: number) => complaints.filter((c) => c.assigned_to_id === surveyorId);

  const filteredSurveyors = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return surveyors;
    return surveyors.filter((s) => [s.name, s.username, s.department?.name].filter(Boolean).join(' ').toLowerCase().includes(q));
  }, [surveyors, search]);

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
  const turnarounds = resolvedTasks.map(turnaroundHours).filter((h): h is number => h !== null);
  const avgTurnaround = turnarounds.length ? Math.round(turnarounds.reduce((a, b) => a + b, 0) / turnarounds.length) : null;

  // Open complaints not already assigned to the selected surveyor - candidates
  // for the "Assign Complaint" action (reuses the existing transfer endpoint).
  const assignableComplaints = complaints.filter(
    (c) => !['Closed', 'Rejected'].includes(c.status) && c.assigned_to_id !== selected?.id,
  );

  const closeModal = () => {
    setSelectedId(null);
    setShowAssign(false);
    setShowReject(false);
    setRejectReason('');
    setAssignComplaintId('');
    setAssignError('');
    setShowDeleteConfirm(false);
  };

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
      setSurveyors((prev) => prev.map((s) => (s.id === selected.id ? { ...s, registration_status: 'active', is_active: true } : s)));
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsApproving(false);
    }
  };

  const handleReject = async () => {
    if (!selected || !rejectReason.trim()) return;
    setIsRejecting(true);
    setError('');
    try {
      await api.rejectRegistration(selected.id, rejectReason.trim());
      setSurveyors((prev) => prev.map((s) => (s.id === selected.id ? { ...s, registration_status: 'rejected', rejection_reason: rejectReason.trim() } : s)));
      setShowReject(false);
      setRejectReason('');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsRejecting(false);
    }
  };

  const confirmDelete = async () => {
    if (!selected) return;
    setIsDeleting(true);
    setError('');
    try {
      await api.deleteUser(selected.id);
      setSurveyors((prev) => prev.filter((s) => s.id !== selected.id));
      setShowDeleteConfirm(false);
      closeModal();
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

      <div className="relative mb-3 max-w-sm">
        <Search className="w-3.5 h-3.5 text-muted absolute left-2.5 top-1/2 -translate-y-1/2" />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search surveyor or department…"
          className="w-full text-xs border border-line rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
        />
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {paginated.length === 0 ? (
          <p className="text-sm text-muted p-6 text-center">No surveyors found.</p>
        ) : (
          <table className="w-full text-xs border-separate border-spacing-0">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-3 font-bold">Surveyor</th>
                <th className="text-left p-3 font-bold">Status</th>
                <th className="text-left p-3 font-bold">Active</th>
                <th className="text-left p-3 font-bold">Completed</th>
                <th className="text-left p-3 font-bold">Joined</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((s, idx) => {
                const active = tasksFor(s.id).filter((c) => SURVEYING_STATUSES.includes(c.status)).length;
                const completed = tasksFor(s.id).filter((c) => RESOLVED_STATUSES.includes(c.status)).length;
                return (
                  <tr
                    key={s.id}
                    onClick={() => setSelectedId(s.id)}
                    className={`border-t border-slate-100 cursor-pointer transition-colors hover:bg-accent/5 ${idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'}`}
                  >
                    <td className="p-3">
                      <div className="flex items-center gap-2.5">
                        <span className="w-8 h-8 rounded-full bg-sidebar text-white font-serif font-semibold text-[12px] flex items-center justify-center shrink-0">
                          {initials(s.name || s.username)}
                        </span>
                        <div className="min-w-0">
                          <p className="font-semibold text-ink truncate">{s.name || s.username}</p>
                          <p className="text-[11px] text-muted truncate">{s.department?.name || s.username}</p>
                        </div>
                      </div>
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
                    <td className="p-3 text-slate-500">
                      {new Date(s.created_at).toLocaleDateString(undefined, { month: 'short', year: 'numeric' })}
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
                </div>
                <p className="text-[12.5px] text-muted">
                  {[selected.department?.name, `Joined ${new Date(selected.created_at).toLocaleDateString(undefined, { month: 'short', year: 'numeric' })}`].filter(Boolean).join(' · ')}
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

            <div className="flex items-center gap-2 mb-6 flex-wrap">
              {selected.registration_status === 'pending_review' ? (
                <>
                  <button
                    disabled={isApproving}
                    onClick={handleApprove}
                    className="flex items-center gap-1.5 bg-status-closed hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                  >
                    <Check className="w-3.5 h-3.5" />
                    {isApproving ? 'Approving…' : 'Approve'}
                  </button>
                  <button
                    onClick={() => setShowReject((v) => !v)}
                    className="flex items-center gap-1.5 border border-status-rejected text-status-rejected hover:bg-status-rejected/10 text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                  >
                    <X className="w-3.5 h-3.5" />
                    Reject
                  </button>
                </>
              ) : (
                <button
                  onClick={() => setShowAssign((v) => !v)}
                  className="flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer"
                >
                  <Plus className="w-3.5 h-3.5" />
                  Assign Complaint
                </button>
              )}
              <button
                disabled={isDeleting}
                onClick={() => setShowDeleteConfirm(true)}
                title="Delete surveyor"
                className="flex items-center justify-center border border-line hover:border-status-rejected hover:text-status-rejected hover:bg-status-rejected/5 disabled:opacity-50 text-muted p-2 rounded-lg cursor-pointer"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>

            {showReject && selected.registration_status === 'pending_review' && (
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
                    {assignableComplaints.map((c) => (
                      <option key={c.id} value={c.id}>
                        #{c.id} · {c.category.name} · {[c.village, c.panchayat].filter(Boolean).join(', ') || 'No location'} · {c.status.replace('_', ' ')}
                      </option>
                    ))}
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
                  const ack = c.timeline.find((t) => t.status === 'Acknowledged')?.created_at;
                  const resolvedAt = c.timeline.find((t) => t.status === 'Resolved')?.created_at;
                  return (
                    <div key={c.id} className="border border-line rounded-xl overflow-hidden">
                      <div className="flex justify-between items-center px-4 py-3.5 border-b border-line">
                        <div>
                          <p className="text-[13.5px] font-semibold text-ink">{c.category.name}{c.village ? ` — ${c.village}` : ''}</p>
                          <p className="text-[11.5px] text-muted mt-0.5">{[c.village, c.panchayat].filter(Boolean).join(' · ') || 'No location'}</p>
                        </div>
                        <span className="font-mono text-[10.5px] text-muted border border-line px-2 py-1 rounded">CMP-{c.id}</span>
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
                        <p className="text-[13.5px] font-semibold text-ink">{c.category.name}{c.village ? ` — ${c.village}` : ''}</p>
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
      {showDeleteConfirm && selected && (
        <div
          className="fixed inset-0 bg-black/40 z-[60] flex items-center justify-center p-6"
          onClick={() => setShowDeleteConfirm(false)}
        >
          <div
            className="bg-white rounded-2xl w-full max-w-sm p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <p className="font-serif font-semibold text-lg text-ink mb-2">Delete surveyor?</p>
            <p className="text-sm text-muted mb-6">
              Delete <b className="text-ink">{selected.name || selected.username}</b>? This permanently removes their account and cannot be undone.
            </p>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setShowDeleteConfirm(false)}
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
