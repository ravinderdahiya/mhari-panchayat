import { useEffect, useState } from 'react';
import {
  ChevronLeft, ChevronRight, Eye, Inbox, Search, Smartphone, Trash2,
  UserRound, UsersRound, X,
} from 'lucide-react';
import * as api from '../services/api';
import type { CitizenProfile, CitizenStats } from '../types';
import type { MasterPagination } from '../services/api';

const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1,
  lastPage: 1,
  perPage: 10,
  total: 0,
  from: null,
  to: null,
};

const EMPTY_STATS: CitizenStats = {
  registeredCitizens: 0,
  activeCitizens: 0,
  complaintsFiled: 0,
};

function visiblePages(currentPage: number, lastPage: number) {
  const count = Math.min(5, lastPage);
  const start = Math.max(1, Math.min(currentPage - 2, lastPage - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

function formatDate(value: string | null, includeTime = false) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    ...(includeTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  }).format(new Date(value));
}

export default function CitizensPage() {
  const [citizens, setCitizens] = useState<CitizenProfile[]>([]);
  const [selected, setSelected] = useState<CitizenProfile | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<CitizenProfile | null>(null);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<'all' | 'active' | 'inactive'>('all');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(10);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [stats, setStats] = useState<CitizenStats>(EMPTY_STATS);
  const [refreshKey, setRefreshKey] = useState(0);
  const [loading, setLoading] = useState(true);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');

    const timer = window.setTimeout(() => {
      api.getCitizens({ page, perPage, query: search, status })
        .then((response) => {
          if (cancelled) return;
          setCitizens(response.citizens);
          setPagination(response.pagination);
          setStats(response.stats);
        })
        .catch((reason: Error) => {
          if (!cancelled) setError(reason.message);
        })
        .finally(() => {
          if (!cancelled) setLoading(false);
        });
    }, 250);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [page, perPage, search, status, refreshKey]);

  const removeCitizen = async () => {
    if (!deleteTarget || deleting) return;

    setDeleting(true);
    setError('');
    try {
      await api.deleteCitizen(deleteTarget.id);
      setDeleteTarget(null);
      if (selected?.id === deleteTarget.id) setSelected(null);

      if (citizens.length === 1 && page > 1) {
        setPage((current) => current - 1);
      } else {
        setRefreshKey((current) => current + 1);
      }
    } catch (reason) {
      setError((reason as Error).message);
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="space-y-4">
      {error && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <StatCard label="Registered Citizens" value={stats.registeredCitizens} tone="text-sidebar" />
        <StatCard label="Active" value={stats.activeCitizens} tone="text-emerald-700" />
        <StatCard label="Complaints Filed" value={stats.complaintsFiled} tone="text-accent" />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[220px] max-w-sm">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={search}
            onChange={(event) => { setSearch(event.target.value); setPage(1); }}
            placeholder="Search name, mobile or email..."
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select
          value={status}
          onChange={(event) => { setStatus(event.target.value as typeof status); setPage(1); }}
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="all">All Statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <span className="text-xs text-slate-400 ml-auto flex items-center gap-1.5">
          <UsersRound className="w-3.5 h-3.5" /> {pagination.total} citizens
        </span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {loading ? (
          <p className="text-sm text-slate-400 p-6 text-center">Loading citizens...</p>
        ) : citizens.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No citizen registrations found.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs min-w-[1150px]">
              <thead>
                <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                  <th className="text-left p-3 w-16">S.No.</th>
                  <th className="text-left p-3">Citizen</th>
                  <th className="text-left p-3">Mobile</th>
                  <th className="text-left p-3">Email</th>
                  <th className="text-left p-3">Source</th>
                  <th className="text-left p-3">Complaints</th>
                  <th className="text-left p-3">Status</th>
                  <th className="text-left p-3">Registered</th>
                  <th className="text-left p-3">Last Login</th>
                  <th className="text-right p-3">Action</th>
                </tr>
              </thead>
              <tbody>
                {citizens.map((citizen, index) => (
                  <tr key={citizen.id} className="border-t border-slate-100 hover:bg-slate-50">
                    <td className="p-3 font-semibold text-slate-500 tabular-nums">
                      {(pagination.currentPage - 1) * pagination.perPage + index + 1}
                    </td>
                    <td className="p-3 font-semibold text-slate-800">{citizen.name || 'Citizen'}</td>
                    <td className="p-3 text-slate-600">
                      <span className="inline-flex items-center gap-1.5"><Smartphone className="w-3.5 h-3.5" />{citizen.mobile}</span>
                    </td>
                    <td className="p-3 text-slate-500">{citizen.email || '—'}</td>
                    <td className="p-3 text-slate-500 capitalize">{citizen.registrationSource.replace(/_/g, ' ')}</td>
                    <td className="p-3 font-semibold text-sidebar">{citizen.complaintsCount}</td>
                    <td className="p-3"><StatusBadge active={citizen.isActive} /></td>
                    <td className="p-3 text-slate-500 whitespace-nowrap">{formatDate(citizen.registeredAt)}</td>
                    <td className="p-3 text-slate-500 whitespace-nowrap">{formatDate(citizen.lastLoginAt, true)}</td>
                    <td className="p-3">
                      <div className="flex items-center justify-end gap-1.5">
                        <button
                          type="button"
                          onClick={() => setSelected(citizen)}
                          className="inline-flex items-center gap-1 rounded-md border border-slate-200 px-2 py-1.5 font-semibold text-slate-600 hover:border-accent hover:text-accent hover:bg-amber-50 cursor-pointer"
                        >
                          <Eye className="w-3.5 h-3.5" /> View
                        </button>
                        <button
                          type="button"
                          onClick={() => setDeleteTarget(citizen)}
                          className="inline-flex items-center gap-1 rounded-md border border-red-200 px-2 py-1.5 font-semibold text-red-600 hover:bg-red-50 cursor-pointer"
                        >
                          <Trash2 className="w-3.5 h-3.5" /> Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {!loading && pagination.total > 0 && (
          <div className="border-t border-slate-200 px-4 py-3 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3 text-[11px] text-slate-500">
              <span>Showing {pagination.from}-{pagination.to} of {pagination.total}</span>
              <label className="flex items-center gap-1.5">
                Rows
                <select
                  value={perPage}
                  onChange={(event) => { setPerPage(Number(event.target.value)); setPage(1); }}
                  className="border border-slate-200 rounded-md bg-white px-2 py-1 outline-none"
                >
                  <option value={10}>10</option>
                  <option value={25}>25</option>
                  <option value={50}>50</option>
                </select>
              </label>
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                aria-label="Previous page"
                disabled={pagination.currentPage <= 1}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                className="p-1.5 border border-slate-200 rounded-md text-slate-500 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50 cursor-pointer"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>
              {visiblePages(pagination.currentPage, pagination.lastPage).map((pageNumber) => (
                <button
                  type="button"
                  key={pageNumber}
                  onClick={() => setPage(pageNumber)}
                  className={`min-w-8 h-8 px-2 rounded-md text-xs font-semibold border cursor-pointer ${pageNumber === pagination.currentPage ? 'bg-accent text-white border-accent' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'}`}
                >
                  {pageNumber}
                </button>
              ))}
              <button
                type="button"
                aria-label="Next page"
                disabled={pagination.currentPage >= pagination.lastPage}
                onClick={() => setPage((current) => Math.min(pagination.lastPage, current + 1))}
                className="p-1.5 border border-slate-200 rounded-md text-slate-500 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50 cursor-pointer"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        )}
      </div>

      {selected && <CitizenDetails citizen={selected} onClose={() => setSelected(null)} />}

      {deleteTarget && (
        <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/45 p-5" onClick={() => { if (!deleting) setDeleteTarget(null); }}>
          <div role="dialog" aria-modal="true" aria-labelledby="delete-citizen-title" className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl" onClick={(event) => event.stopPropagation()}>
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-full bg-red-50 text-red-600">
              <Trash2 className="h-5 w-5" />
            </div>
            <h2 id="delete-citizen-title" className="text-lg font-bold text-slate-900">Delete citizen?</h2>
            <p className="mt-2 text-sm leading-6 text-slate-500">
              <b className="text-slate-800">{deleteTarget.name || deleteTarget.mobile}</b> का account और उससे जुड़ी complaints permanently delete हो जाएंगी। यह action undo नहीं हो सकता।
            </p>
            <div className="mt-6 flex justify-end gap-2">
              <button type="button" disabled={deleting} onClick={() => setDeleteTarget(null)} className="rounded-lg border border-slate-200 px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50">
                Cancel
              </button>
              <button type="button" disabled={deleting} onClick={removeCitizen} className="inline-flex items-center gap-1.5 rounded-lg bg-red-600 px-4 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:opacity-50">
                <Trash2 className="h-3.5 w-3.5" /> {deleting ? 'Deleting...' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value, tone }: { label: string; value: number; tone: string }) {
  return (
    <div className="bg-white border border-line rounded-xl p-4">
      <p className="text-[10px] uppercase tracking-wide text-muted">{label}</p>
      <p className={`mt-1 text-2xl font-serif font-semibold ${tone}`}>{value}</p>
    </div>
  );
}

function StatusBadge({ active }: { active: boolean }) {
  return (
    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${active ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-slate-100 text-slate-500 border-slate-200'}`}>
      {active ? 'Active' : 'Inactive'}
    </span>
  );
}

function CitizenDetails({ citizen, onClose }: { citizen: CitizenProfile; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/45 p-5" onClick={onClose}>
      <div role="dialog" aria-modal="true" aria-labelledby="citizen-detail-title" className="w-full max-w-2xl rounded-2xl bg-white shadow-xl" onClick={(event) => event.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-slate-200 px-5 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-amber-50 text-accent"><UserRound className="h-5 w-5" /></div>
            <div>
              <h2 id="citizen-detail-title" className="font-serif text-lg font-semibold text-slate-900">{citizen.name || 'Citizen'}</h2>
              <p className="text-[11px] text-slate-500">Citizen ID: {citizen.id}</p>
            </div>
          </div>
          <button type="button" aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-100 cursor-pointer"><X className="h-4 w-4" /></button>
        </div>
        <div className="grid grid-cols-1 gap-3 p-5 sm:grid-cols-2">
          <Info label="Name" value={citizen.name || 'Citizen'} />
          <Info label="Mobile" value={`+91 ${citizen.mobile}`} />
          <Info label="Email" value={citizen.email || '—'} />
          <Info label="Status" value={citizen.isActive ? 'Active' : 'Inactive'} />
          <Info label="Registration source" value={citizen.registrationSource.replace(/_/g, ' ')} />
          <Info label="Complaints filed" value={String(citizen.complaintsCount)} />
          <Info label="Registered on" value={formatDate(citizen.registeredAt, true)} />
          <Info label="Last login" value={formatDate(citizen.lastLoginAt, true)} />
        </div>
        <div className="flex justify-end border-t border-slate-200 px-5 py-3">
          <button type="button" onClick={onClose} className="rounded-lg bg-sidebar px-4 py-2 text-xs font-bold text-white hover:opacity-90 cursor-pointer">Close</button>
        </div>
      </div>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-slate-100 bg-slate-50 p-3">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{label}</p>
      <p className="mt-1 text-sm font-medium text-slate-800 capitalize">{value}</p>
    </div>
  );
}
