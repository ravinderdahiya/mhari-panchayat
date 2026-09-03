import { useEffect, useState } from 'react';
import {
  Camera, ChevronLeft, ChevronRight, ClipboardCheck, Eye, MapPin, Search, X,
} from 'lucide-react';
import * as api from '../services/api';
import type { AssetSurvey, AssetSurveyPagination, AssetSurveyReviewStatus, AssetSurveyStats } from '../types';

const REVIEW_BADGE: Record<AssetSurveyReviewStatus, string> = {
  pending: 'bg-amber-50 text-amber-800 border-amber-200',
  returned: 'bg-orange-50 text-orange-700 border-orange-200',
  gram_sachiv_approved: 'bg-sky-50 text-sky-700 border-sky-200',
  bdpo_forwarded: 'bg-indigo-50 text-indigo-700 border-indigo-200',
  approved: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  rejected: 'bg-red-50 text-red-700 border-red-200',
};

const REVIEW_LABEL: Record<AssetSurveyReviewStatus, string> = {
  pending: 'Pending review',
  returned: 'Returned for correction',
  gram_sachiv_approved: 'Verified by Gram Sachiv',
  bdpo_forwarded: 'Forwarded by BDPO',
  approved: 'Approved',
  rejected: 'Rejected',
};

const CONDITION_STYLE: Record<AssetSurvey['condition'], string> = {
  GOOD: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  FAIR: 'bg-blue-50 text-blue-700 border-blue-200',
  POOR: 'bg-amber-50 text-amber-800 border-amber-200',
  DAMAGED: 'bg-red-50 text-red-700 border-red-200',
};

const ACTION_PAST_TENSE: Record<string, string> = {
  verified: 'Verified',
  returned: 'Returned for correction',
  forwarded: 'Forwarded',
  approved: 'Approved',
  rejected: 'Rejected',
};

const EMPTY_PAGINATION: AssetSurveyPagination = {
  currentPage: 1, lastPage: 1, perPage: 10, total: 0, from: null, to: null,
};

const EMPTY_STATS: AssetSurveyStats = {
  totalSurveys: 0, activeSurveyors: 0, poorDamaged: 0,
  statusCounts: {
    pending: 0, returned: 0, gram_sachiv_approved: 0, bdpo_forwarded: 0, approved: 0, rejected: 0,
  },
};

const STATUS_FILTERS: Array<{ id: 'all' | AssetSurveyReviewStatus; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'pending', label: 'Pending' },
  { id: 'returned', label: 'Returned' },
  { id: 'gram_sachiv_approved', label: 'Verified' },
  { id: 'bdpo_forwarded', label: 'Forwarded' },
  { id: 'approved', label: 'Approved' },
  { id: 'rejected', label: 'Rejected' },
];

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date(value));
}

function visiblePages(currentPage: number, lastPage: number) {
  const count = Math.min(5, lastPage);
  const start = Math.max(1, Math.min(currentPage - 2, lastPage - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

export default function MySurveysPage() {
  const [surveys, setSurveys] = useState<AssetSurvey[]>([]);
  const [selected, setSelected] = useState<AssetSurvey | null>(null);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | AssetSurveyReviewStatus>('all');
  const [page, setPage] = useState(1);
  const [pagination, setPagination] = useState<AssetSurveyPagination>(EMPTY_PAGINATION);
  const [stats, setStats] = useState<AssetSurveyStats>(EMPTY_STATS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => { setPage(1); }, [statusFilter, query]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    const timer = window.setTimeout(() => {
      api.getAssetSurveys({
        page,
        perPage: 10,
        query,
        reviewStatus: statusFilter === 'all' ? undefined : statusFilter,
      })
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
  }, [page, query, statusFilter]);

  const statusCount = (id: 'all' | AssetSurveyReviewStatus) => (
    id === 'all' ? stats.totalSurveys : stats.statusCounts[id]
  );

  return (
    <div className="space-y-4">
      {error && (
        <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {STATUS_FILTERS.map((filter) => (
          <button
            key={filter.id}
            type="button"
            onClick={() => setStatusFilter(filter.id)}
            className={`text-[11px] font-bold px-3 py-1.5 rounded-full border cursor-pointer ${
              statusFilter === filter.id
                ? 'bg-accent text-white border-accent'
                : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
            }`}
          >
            {filter.label}
            <span className={`ml-1.5 ${statusFilter === filter.id ? 'text-white/80' : 'text-slate-400'}`}>
              {statusCount(filter.id)}
            </span>
          </button>
        ))}
        <div className="relative ml-auto min-w-[220px] flex-1 max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search asset, village or panchayat"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {loading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : surveys.length === 0 ? (
          <div className="p-10 text-center">
            <ClipboardCheck className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">
              {stats.totalSurveys === 0
                ? 'You have not submitted any field surveys yet.'
                : 'No surveys match this filter.'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                  <th className="text-left p-2.5">S.No.</th>
                  <th className="text-left p-2.5">Asset</th>
                  <th className="text-left p-2.5">Department / Type</th>
                  <th className="text-left p-2.5">Location</th>
                  <th className="text-left p-2.5">Condition</th>
                  <th className="text-left p-2.5">Survey date</th>
                  <th className="text-left p-2.5">Status</th>
                  <th className="text-right p-2.5">Action</th>
                </tr>
              </thead>
              <tbody>
                {surveys.map((survey, index) => (
                  <tr key={survey.id} className="border-t border-slate-100 hover:bg-slate-50">
                    <td className="p-2.5 text-slate-400">
                      {(pagination.currentPage - 1) * pagination.perPage + index + 1}
                    </td>
                    <td className="p-2.5">
                      <p className="font-semibold text-slate-800">{survey.assetName}</p>
                      <p className="font-mono text-[10px] text-slate-400 mt-0.5">{survey.assetId}</p>
                    </td>
                    <td className="p-2.5 text-slate-600">
                      <p>{survey.departmentName || '—'}</p>
                      <p className="text-[10px] text-slate-400">{survey.assetTypeName || '—'}</p>
                    </td>
                    <td className="p-2.5 text-slate-600">
                      <p>{survey.village}</p>
                      <p className="text-[10px] text-slate-400">{survey.panchayat}, {survey.district}</p>
                    </td>
                    <td className="p-2.5">
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${CONDITION_STYLE[survey.condition]}`}>
                        {survey.condition}
                      </span>
                    </td>
                    <td className="p-2.5 text-slate-400 whitespace-nowrap">{formatDate(survey.surveyDate)}</td>
                    <td className="p-2.5">
                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${REVIEW_BADGE[survey.reviewStatus]}`}>
                        {REVIEW_LABEL[survey.reviewStatus]}
                      </span>
                    </td>
                    <td className="p-2.5 text-right">
                      <button
                        type="button"
                        onClick={() => setSelected(survey)}
                        className="inline-flex items-center gap-1 text-xs font-semibold text-accent hover:underline cursor-pointer"
                      >
                        <Eye className="w-3.5 h-3.5" /> View
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!loading && pagination.total > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {pagination.from ?? 0}–{pagination.to ?? 0} of {pagination.total}</span>
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={pagination.currentPage <= 1}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                className="p-1.5 border border-slate-200 rounded-md disabled:opacity-40"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
              </button>
              {visiblePages(pagination.currentPage, pagination.lastPage).map((pageNumber) => (
                <button
                  type="button"
                  key={pageNumber}
                  onClick={() => setPage(pageNumber)}
                  className={`min-w-8 h-8 px-2 rounded-md text-xs font-semibold border ${
                    pageNumber === pagination.currentPage
                      ? 'bg-accent text-white border-accent'
                      : 'bg-white text-slate-700 border-slate-200'
                  }`}
                >
                  {pageNumber}
                </button>
              ))}
              <button
                type="button"
                disabled={pagination.currentPage >= pagination.lastPage}
                onClick={() => setPage((current) => Math.min(pagination.lastPage, current + 1))}
                className="p-1.5 border border-slate-200 rounded-md disabled:opacity-40"
              >
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {selected && (
        <SurveyDetails survey={selected} onClose={() => setSelected(null)} />
      )}
    </div>
  );
}

function SurveyDetails({ survey, onClose }: { survey: AssetSurvey; onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/45 z-[70] flex items-center justify-center p-5" onClick={onClose}>
      <div
        className="bg-white rounded-2xl w-full max-w-3xl max-h-[90vh] overflow-y-auto"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="sticky top-0 bg-white border-b border-slate-100 px-5 py-4 flex items-center justify-between z-10">
          <div>
            <div className="flex items-center gap-2">
              <h2 className="font-semibold text-lg text-slate-900">{survey.assetName}</h2>
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${REVIEW_BADGE[survey.reviewStatus]}`}>
                {REVIEW_LABEL[survey.reviewStatus]}
              </span>
            </div>
            <p className="font-mono text-[10px] text-slate-400">{survey.assetId}</p>
          </div>
          <button type="button" onClick={onClose} className="p-1.5 rounded-lg hover:bg-slate-50">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-5 space-y-5">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Info label="Department" value={survey.departmentName || '—'} />
            <Info label="Asset type" value={survey.assetTypeName || '—'} />
            <Info label="Condition" value={survey.condition} />
            <Info label="Village / Panchayat" value={`${survey.village}, ${survey.panchayat}`} />
            <Info label="District" value={survey.district} />
            <Info label="Survey date" value={formatDate(survey.surveyDate)} />
            <Info label="GPS" value={`${survey.latitude.toFixed(6)}, ${survey.longitude.toFixed(6)}`} />
          </div>

          {survey.description && (
            <div>
              <p className="text-[10px] uppercase tracking-wide text-slate-400 mb-1">Description</p>
              <p className="text-sm text-slate-800 bg-slate-50 rounded-lg p-3">{survey.description}</p>
            </div>
          )}

          {(survey.reviewStatus === 'rejected' || survey.reviewStatus === 'returned') && survey.rejectionReason && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3">
              <p className="text-[10px] uppercase tracking-wide text-red-600 mb-1">
                {survey.reviewStatus === 'returned' ? 'Correction needed' : 'Rejection reason'}
              </p>
              <p className="text-sm text-red-800">{survey.rejectionReason}</p>
            </div>
          )}

          <a
            href={`https://www.google.com/maps?q=${survey.latitude},${survey.longitude}`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-xs font-semibold text-accent hover:underline"
          >
            <MapPin className="w-3.5 h-3.5" /> Open GPS location
          </a>

          <div>
            <p className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-slate-400 mb-2">
              <Camera className="w-3.5 h-3.5" /> Survey photos ({survey.photoUrls.length})
            </p>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {survey.photoUrls.map((url, index) => (
                <a
                  key={url}
                  href={api.mediaUrl(url)}
                  target="_blank"
                  rel="noreferrer"
                  className="block aspect-[4/3] rounded-lg overflow-hidden border border-slate-200 bg-slate-50"
                >
                  <img src={api.mediaUrl(url)} alt={`Survey ${index + 1}`} className="w-full h-full object-cover" />
                </a>
              ))}
            </div>
          </div>

          {survey.reviews.length > 0 && (
            <div>
              <p className="text-[10px] uppercase tracking-wide text-slate-400 mb-2">Approval history</p>
              <div className="space-y-2">
                {survey.reviews.map((review, index) => (
                  <div key={index} className="border border-slate-200 rounded-lg p-3 text-xs text-slate-500">
                    <span className="font-semibold text-slate-800">{ACTION_PAST_TENSE[review.action] ?? review.action}</span>
                    {' by '}{review.actorName || 'admin'} ({review.actorRole})
                    {review.createdAt ? ` on ${formatDate(review.createdAt)}` : ''}
                    {review.remarks && <p className="text-red-600 mt-1">Reason: {review.remarks}</p>}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="border border-slate-200 rounded-lg p-3">
      <p className="text-[10px] uppercase tracking-wide text-slate-400">{label}</p>
      <p className="text-xs font-medium text-slate-800 mt-1">{value}</p>
    </div>
  );
}
