import { Fragment, useEffect, useState } from 'react';
import { Camera, Check, ChevronLeft, ChevronRight, ClipboardList, Eye, MapPin, Search, ShieldAlert, Trash2, UserRound, X } from 'lucide-react';
import * as api from '../services/api';
import type { AssetSurvey, AssetSurveyPagination, AssetSurveyStats } from '../types';

type ReviewStatus = 'pending' | 'approved' | 'rejected';

const CHILD_TO_REVIEW_STATUS: Record<string, ReviewStatus> = {
  'pending-review': 'pending',
  approved: 'approved',
  rejected: 'rejected',
};

const REVIEW_BADGE: Record<ReviewStatus, string> = {
  pending: 'bg-amber-50 text-amber-800 border-amber-200',
  approved: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  rejected: 'bg-red-50 text-red-700 border-red-200',
};

const REVIEW_LABEL: Record<ReviewStatus, string> = {
  pending: 'Pending review',
  approved: 'Approved',
  rejected: 'Rejected',
};

function ReviewBadge({ value }: { value: ReviewStatus }) {
  return <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${REVIEW_BADGE[value]}`}>{REVIEW_LABEL[value]}</span>;
}

const CONDITION_STYLE: Record<AssetSurvey['condition'], string> = {
  GOOD: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  FAIR: 'bg-blue-50 text-blue-700 border-blue-200',
  POOR: 'bg-amber-50 text-amber-800 border-amber-200',
  DAMAGED: 'bg-red-50 text-red-700 border-red-200',
};

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date(value));
}

function ConditionBadge({ value }: { value: AssetSurvey['condition'] }) {
  return <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${CONDITION_STYLE[value]}`}>{value}</span>;
}

const EMPTY_PAGINATION: AssetSurveyPagination = {
  currentPage: 1, lastPage: 1, perPage: 10, total: 0, from: null, to: null,
};

const EMPTY_STATS: AssetSurveyStats = {
  totalSurveys: 0, activeSurveyors: 0, poorDamaged: 0,
  statusCounts: { pending: 0, approved: 0, rejected: 0 },
};

function visiblePages(currentPage: number, lastPage: number) {
  const count = Math.min(5, lastPage);
  const start = Math.max(1, Math.min(currentPage - 2, lastPage - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

interface AssetSurveysPageProps {
  // Sidebar sub-item id: 'pending-review' | 'approved' | 'rejected'.
  childId?: string;
}

export default function AssetSurveysPage({ childId }: AssetSurveysPageProps) {
  const reviewStatus = CHILD_TO_REVIEW_STATUS[childId ?? ''] ?? 'pending';

  const [surveys, setSurveys] = useState<AssetSurvey[]>([]);
  const [selected, setSelected] = useState<AssetSurvey | null>(null);
  const [query, setQuery] = useState('');
  const [condition, setCondition] = useState('ALL');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(10);
  const [pagination, setPagination] = useState<AssetSurveyPagination>(EMPTY_PAGINATION);
  const [stats, setStats] = useState<AssetSurveyStats>(EMPTY_STATS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [actionError, setActionError] = useState('');
  const [actioningId, setActioningId] = useState<string | null>(null);
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  // Switching tabs (Pending/Approved/Rejected) should feel like a fresh list,
  // not a page you scrolled down on.
  useEffect(() => { setPage(1); }, [reviewStatus]);

  // Bumped after an approve/reject to force the fetch effect below to re-run
  // (the surveyed-out row is also removed from local state immediately, so
  // this mainly re-syncs stats/pagination with the server).
  const [refreshTick, setRefreshTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    const timer = window.setTimeout(() => {
      api.getAssetSurveys({ page, perPage, query, condition, reviewStatus })
        .then((response) => {
          if (cancelled) return;
          setSurveys(response.surveys);
          setPagination(response.pagination);
          setStats(response.stats);
        })
        .catch((err) => {
          if (!cancelled) setError((err as Error).message);
        })
        .finally(() => {
          if (!cancelled) setLoading(false);
        });
    }, 250);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [page, perPage, query, condition, reviewStatus, refreshTick]);

  const handleApprove = async (survey: AssetSurvey) => {
    setActioningId(survey.id);
    setActionError('');
    try {
      await api.approveAssetSurvey(survey.id);
      setSurveys((prev) => prev.filter((s) => s.id !== survey.id));
      setSelected(null);
      setRefreshTick((t) => t + 1);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setActioningId(null);
    }
  };

  const handleDelete = async (survey: AssetSurvey) => {
    if (!confirm(`Delete survey for "${survey.assetName}"? This cannot be undone.`)) return;
    setActioningId(survey.id);
    setActionError('');
    try {
      await api.deleteAssetSurvey(survey.id);
      setSurveys((prev) => prev.filter((s) => s.id !== survey.id));
      setSelected(null);
      setRefreshTick((t) => t + 1);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setActioningId(null);
    }
  };

  const handleReject = async (survey: AssetSurvey, reason: string) => {
    if (!reason.trim()) return;
    setActioningId(survey.id);
    setActionError('');
    try {
      await api.rejectAssetSurvey(survey.id, reason.trim());
      setSurveys((prev) => prev.filter((s) => s.id !== survey.id));
      setSelected(null);
      setRejectingId(null);
      setRejectReason('');
      setRefreshTick((t) => t + 1);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setActioningId(null);
    }
  };

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Stat label="Total surveys" value={stats.totalSurveys} icon={<ClipboardList className="w-4 h-4" />} />
        <Stat label="Active surveyors" value={stats.activeSurveyors} icon={<UserRound className="w-4 h-4" />} />
        <Stat label="Poor / damaged" value={stats.poorDamaged} icon={<MapPin className="w-4 h-4" />} />
      </div>

      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-ink flex items-center gap-2">
          {REVIEW_LABEL[reviewStatus]}
          <span className="text-[11px] font-normal text-muted">({stats.statusCounts[reviewStatus]})</span>
        </h2>
      </div>

      <div className="bg-white border border-line rounded-xl p-3 flex flex-wrap gap-3 items-center">
        <div className="relative min-w-[240px] flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted" />
          <input value={query} onChange={(event) => { setQuery(event.target.value); setPage(1); }}
            placeholder="Search asset, surveyor, department or village"
            className="w-full pl-9 pr-3 py-2 text-xs border border-line rounded-lg outline-none focus:ring-2 focus:ring-accent/30" />
        </div>
        <select value={condition} onChange={(event) => { setCondition(event.target.value); setPage(1); }}
          className="text-xs border border-line rounded-lg px-3 py-2 bg-white outline-none">
          <option value="ALL">All conditions</option><option value="GOOD">Good</option>
          <option value="FAIR">Fair</option><option value="POOR">Poor</option><option value="DAMAGED">Damaged</option>
        </select>
      </div>

      {error && <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">{error}</p>}
      {actionError && <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">{actionError}</p>}

      <div className="bg-white border border-line rounded-xl overflow-hidden">
        {loading ? <p className="p-8 text-sm text-muted text-center">Loading asset surveys…</p>
          : surveys.length === 0 ? <p className="p-8 text-sm text-muted text-center">No {REVIEW_LABEL[reviewStatus].toLowerCase()} surveys found.</p>
          : <div className="overflow-x-auto"><table className="w-full text-left">
            <thead className="bg-cream border-b border-line text-[10px] uppercase tracking-wide text-muted"><tr>
              <th className="px-4 py-3 w-16">S.No.</th><th className="px-4 py-3">Asset</th><th className="px-4 py-3">Surveyor</th>
              <th className="px-4 py-3">Department / Type</th><th className="px-4 py-3">Location</th>
              <th className="px-4 py-3">Condition</th><th className="px-4 py-3">Survey date</th>
              <th className="px-4 py-3">Review</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr></thead>
            <tbody className="divide-y divide-line">{surveys.map((survey, index) => <Fragment key={survey.id}>
              <tr className="hover:bg-cream/40">
                <td className="px-4 py-3 text-xs font-semibold text-muted">{(pagination.currentPage - 1) * pagination.perPage + index + 1}</td>
                <td className="px-4 py-3"><p className="text-xs font-semibold text-ink">{survey.assetName}</p><p className="font-mono text-[10px] text-muted mt-0.5">{survey.assetId}</p></td>
                <td className="px-4 py-3"><p className="text-xs font-medium text-ink">{survey.surveyedByName || 'Unknown'}</p><p className="text-[10px] text-muted">{survey.surveyor?.employeeId || survey.surveyor?.username}</p></td>
                <td className="px-4 py-3"><p className="text-xs text-ink">{survey.departmentName}</p><p className="text-[10px] text-muted">{survey.assetTypeName}</p></td>
                <td className="px-4 py-3"><p className="text-xs text-ink">{survey.village}</p><p className="text-[10px] text-muted">{survey.panchayat}, {survey.district}</p></td>
                <td className="px-4 py-3"><ConditionBadge value={survey.condition} /></td>
                <td className="px-4 py-3 text-[11px] text-muted whitespace-nowrap">{formatDate(survey.surveyDate)}</td>
                <td className="px-4 py-3">
                  <ReviewBadge value={survey.reviewStatus} />
                  {survey.reviewStatus === 'rejected' && survey.rejectionReason && (
                    <p className="text-[10px] text-red-600 mt-1 max-w-[160px]" title={survey.rejectionReason}>{survey.rejectionReason}</p>
                  )}
                </td>
                <td className="px-4 py-3 text-right">
                  <div className="flex items-center justify-end gap-2.5 flex-wrap">
                    <button onClick={() => setSelected(survey)} className="inline-flex items-center gap-1 text-xs font-semibold text-accent hover:underline cursor-pointer"><Eye className="w-3.5 h-3.5" /> View</button>
                    {survey.reviewStatus === 'pending' && (
                      <>
                        <button disabled={actioningId === survey.id} onClick={() => handleApprove(survey)}
                          className="inline-flex items-center gap-1 text-xs font-semibold text-emerald-700 hover:underline disabled:opacity-50 cursor-pointer">
                          <Check className="w-3.5 h-3.5" /> Approve
                        </button>
                        <button disabled={actioningId === survey.id} onClick={() => { setRejectingId(survey.id); setRejectReason(''); }}
                          className="inline-flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50 cursor-pointer">
                          <ShieldAlert className="w-3.5 h-3.5" /> Reject
                        </button>
                      </>
                    )}
                    <button disabled={actioningId === survey.id} onClick={() => handleDelete(survey)}
                      className="inline-flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50 cursor-pointer">
                      <Trash2 className="w-3.5 h-3.5" /> Delete
                    </button>
                  </div>
                </td>
              </tr>
              {rejectingId === survey.id && (
                <tr className="bg-red-50/40">
                  <td colSpan={9} className="px-4 py-3">
                    <div className="flex gap-2 items-center">
                      <input value={rejectReason} onChange={(event) => setRejectReason(event.target.value)}
                        placeholder="Reason for rejection…" autoFocus
                        className="flex-1 text-xs border border-line rounded-lg px-2.5 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-red-300" />
                      <button disabled={!rejectReason.trim() || actioningId === survey.id} onClick={() => handleReject(survey, rejectReason)}
                        className="bg-red-600 hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer">
                        {actioningId === survey.id ? 'Rejecting…' : 'Confirm reject'}
                      </button>
                      <button onClick={() => { setRejectingId(null); setRejectReason(''); }}
                        className="text-xs font-bold px-3 py-2 rounded-lg border border-line text-muted hover:bg-white cursor-pointer">
                        Cancel
                      </button>
                    </div>
                  </td>
                </tr>
              )}
            </Fragment>)}</tbody>
          </table></div>}
        {!loading && pagination.total > 0 && <div className="border-t border-line px-4 py-3 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3 text-[11px] text-muted">
            <span>Showing {pagination.from}-{pagination.to} of {pagination.total}</span>
            <label className="flex items-center gap-1.5">Rows
              <select value={perPage} onChange={(event) => { setPerPage(Number(event.target.value)); setPage(1); }}
                className="border border-line rounded-md bg-white px-2 py-1 outline-none">
                <option value={10}>10</option><option value={25}>25</option><option value={50}>50</option>
              </select>
            </label>
          </div>
          <div className="flex items-center gap-1">
            <button type="button" aria-label="Previous page" disabled={pagination.currentPage <= 1}
              onClick={() => setPage((current) => Math.max(1, current - 1))}
              className="p-1.5 border border-line rounded-md text-muted disabled:opacity-40 disabled:cursor-not-allowed hover:bg-cream cursor-pointer">
              <ChevronLeft className="w-4 h-4" />
            </button>
            {visiblePages(pagination.currentPage, pagination.lastPage).map((pageNumber) =>
              <button type="button" key={pageNumber} onClick={() => setPage(pageNumber)}
                className={`min-w-8 h-8 px-2 rounded-md text-xs font-semibold border cursor-pointer ${pageNumber === pagination.currentPage ? 'bg-accent text-white border-accent' : 'bg-white text-ink border-line hover:bg-cream'}`}>
                {pageNumber}
              </button>)}
            <button type="button" aria-label="Next page" disabled={pagination.currentPage >= pagination.lastPage}
              onClick={() => setPage((current) => Math.min(pagination.lastPage, current + 1))}
              className="p-1.5 border border-line rounded-md text-muted disabled:opacity-40 disabled:cursor-not-allowed hover:bg-cream cursor-pointer">
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>}
      </div>

      {selected && (
        <SurveyDetails
          survey={selected}
          onClose={() => setSelected(null)}
          onApprove={() => handleApprove(selected)}
          onReject={(reason) => handleReject(selected, reason)}
          onDelete={() => handleDelete(selected)}
          isActioning={actioningId === selected.id}
        />
      )}
    </div>
  );
}

function Stat({ label, value, icon }: { label: string; value: number; icon: React.ReactNode }) {
  return <div className="bg-white border border-line rounded-xl p-4 flex items-center gap-3">
    <div className="w-9 h-9 rounded-lg bg-accent-soft text-accent flex items-center justify-center">{icon}</div>
    <div><p className="text-xl font-serif font-semibold text-ink">{value}</p><p className="text-[11px] text-muted">{label}</p></div>
  </div>;
}

function SurveyDetails({ survey, onClose, onApprove, onReject, onDelete, isActioning }: {
  survey: AssetSurvey;
  onClose: () => void;
  onApprove: () => void;
  onReject: (reason: string) => void;
  onDelete: () => void;
  isActioning: boolean;
}) {
  const [showReject, setShowReject] = useState(false);
  const [reason, setReason] = useState('');

  return <div className="fixed inset-0 bg-black/45 z-[70] flex items-center justify-center p-5" onClick={onClose}>
    <div className="bg-white rounded-2xl w-full max-w-3xl max-h-[90vh] overflow-y-auto" onClick={(event) => event.stopPropagation()}>
      <div className="sticky top-0 bg-white border-b border-line px-5 py-4 flex items-center justify-between z-10">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="font-serif text-lg font-semibold text-ink">{survey.assetName}</h2>
            <ReviewBadge value={survey.reviewStatus} />
          </div>
          <p className="font-mono text-[10px] text-muted">{survey.assetId}</p>
        </div>
        <div className="flex items-center gap-1.5">
          <button disabled={isActioning} onClick={onDelete}
            className="flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50 cursor-pointer px-1.5">
            <Trash2 className="w-3.5 h-3.5" /> Delete
          </button>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-cream cursor-pointer"><X className="w-4 h-4" /></button>
        </div>
      </div>
      <div className="p-5 space-y-5">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Info label="Surveyor" value={`${survey.surveyedByName || 'Unknown'}${survey.surveyor?.employeeId ? ` (${survey.surveyor.employeeId})` : ''}`} />
          <Info label="Department" value={survey.departmentName || '—'} /><Info label="Asset type" value={survey.assetTypeName || '—'} />
          <Info label="Condition" value={survey.condition} /><Info label="Village / Panchayat" value={`${survey.village}, ${survey.panchayat}`} />
          <Info label="District" value={survey.district} /><Info label="Survey date" value={formatDate(survey.surveyDate)} />
          <Info label="GPS" value={`${survey.latitude.toFixed(6)}, ${survey.longitude.toFixed(6)}`} />
        </div>
        {survey.description && <div><p className="text-[10px] uppercase tracking-wide text-muted mb-1">Description</p><p className="text-sm text-ink bg-cream rounded-lg p-3">{survey.description}</p></div>}
        <a href={`https://www.google.com/maps?q=${survey.latitude},${survey.longitude}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1.5 text-xs font-semibold text-accent hover:underline"><MapPin className="w-3.5 h-3.5" /> Open GPS location</a>
        <div><p className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-muted mb-2"><Camera className="w-3.5 h-3.5" /> Survey photos ({survey.photoUrls.length})</p>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">{survey.photoUrls.map((url, index) =>
            <a key={url} href={api.mediaUrl(url)} target="_blank" rel="noreferrer" className="block aspect-[4/3] rounded-lg overflow-hidden border border-line bg-cream"><img src={api.mediaUrl(url)} alt={`Survey ${index + 1}`} className="w-full h-full object-cover" /></a>)}</div>
        </div>

        {survey.reviewStatus !== 'pending' && (
          <div className="border border-line rounded-lg p-3 text-xs text-muted">
            {survey.reviewStatus === 'approved' ? 'Approved' : 'Rejected'} by {survey.reviewedByName || 'admin'}
            {survey.reviewedAt ? ` on ${formatDate(survey.reviewedAt)}` : ''}
            {survey.reviewStatus === 'rejected' && survey.rejectionReason && (
              <p className="text-red-600 mt-1">Reason: {survey.rejectionReason}</p>
            )}
          </div>
        )}

        {survey.reviewStatus === 'pending' && (
          <div className="border-t border-line pt-4">
            {!showReject ? (
              <div className="flex gap-2">
                <button disabled={isActioning} onClick={onApprove}
                  className="flex items-center gap-1.5 bg-emerald-600 hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer">
                  <Check className="w-3.5 h-3.5" /> {isActioning ? 'Approving…' : 'Approve survey'}
                </button>
                <button disabled={isActioning} onClick={() => setShowReject(true)}
                  className="flex items-center gap-1.5 border border-red-300 text-red-700 hover:bg-red-50 disabled:opacity-50 text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer">
                  <ShieldAlert className="w-3.5 h-3.5" /> Reject survey
                </button>
              </div>
            ) : (
              <div className="flex gap-2">
                <input value={reason} onChange={(event) => setReason(event.target.value)}
                  placeholder="Reason for rejection…" autoFocus
                  className="flex-1 text-xs border border-line rounded-lg px-2.5 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-red-300" />
                <button disabled={!reason.trim() || isActioning} onClick={() => onReject(reason)}
                  className="bg-red-600 hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer">
                  {isActioning ? 'Rejecting…' : 'Confirm reject'}
                </button>
                <button onClick={() => { setShowReject(false); setReason(''); }}
                  className="text-xs font-bold px-3 py-2 rounded-lg border border-line text-muted hover:bg-cream cursor-pointer">
                  Cancel
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  </div>;
}

function Info({ label, value }: { label: string; value: string }) {
  return <div className="border border-line rounded-lg p-3"><p className="text-[10px] uppercase tracking-wide text-muted">{label}</p><p className="text-xs font-medium text-ink mt-1">{value}</p></div>;
}
