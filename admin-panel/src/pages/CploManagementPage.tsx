import { useEffect, useMemo, useState } from 'react';
import { Search, MapPin, Trash2, X, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react';
import * as api from '../services/api';
import type { AdminUser, Block, District, Panchayat } from '../types';

const PAGE_SIZE = 10;

// CPLO isn't a separate system role - it's a Surveyor (role `surveyor`) who
// has been given a single panchayat, restricting them (via the existing
// department-assignment scoping) to Panchayati Raj asset surveys for that
// panchayat. This tab is just that assignment UI; "Surveyor" here means the
// full surveyor-role list, most of whom won't have a panchayat set at all.
const TABS = [
  { role: 'surveyor', label: 'Surveyor (CPLO)', hint: 'Give a Surveyor a panchayat to act as CPLO - scoped to Panchayati Raj surveys for that panchayat only.' },
  { role: 'gram_sachiv', label: 'Gram Sachiv', hint: 'Verifies (approves/rejects) surveys submitted for their assigned panchayat.' },
] as const;

function initials(name: string) {
  return name.split(' ').filter(Boolean).slice(0, 2).map((n) => n[0]!.toUpperCase()).join('') || '?';
}

export default function CploManagementPage() {
  const [role, setRole] = useState<(typeof TABS)[number]['role']>('surveyor');
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const [districts, setDistricts] = useState<District[]>([]);
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [panchayats, setPanchayats] = useState<Panchayat[]>([]);
  const [masterLoaded, setMasterLoaded] = useState(false);

  const [assignTarget, setAssignTarget] = useState<AdminUser | null>(null);
  const [assignDistrictId, setAssignDistrictId] = useState<number | ''>('');
  const [assignBlockId, setAssignBlockId] = useState<number | ''>('');
  const [assignPanchayatId, setAssignPanchayatId] = useState<number | ''>('');
  const [isSavingAssignment, setIsSavingAssignment] = useState(false);
  const [assignError, setAssignError] = useState('');

  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const load = async () => {
    setIsLoading(true);
    setError('');
    try {
      const { users: all } = await api.getUsers();
      setUsers(all.filter((u) => u.role === role));
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [role]);

  useEffect(() => { setPage(1); setSearch(''); }, [role]);

  // District/Block/Panchayat master lists are only needed once an assignment
  // modal is opened - mirrors SurveyorsPage's lazy-load-on-demand pattern for
  // its (much larger) village master list.
  useEffect(() => {
    if (!assignTarget || masterLoaded) return;
    Promise.all([
      api.masterApi('districts').list(),
      api.masterApi('blocks').list(),
      api.masterApi('panchayats').list(),
    ])
      .then(([districtRes, blockRes, panchayatRes]) => {
        setDistricts(districtRes.items || []);
        setBlocks(blockRes.items || []);
        setPanchayats(panchayatRes.items || []);
        setMasterLoaded(true);
      })
      .catch((err) => setAssignError((err as Error).message));
  }, [assignTarget, masterLoaded]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return users;
    return users.filter((u) =>
      [u.name, u.username, u.mobile, u.district?.name, u.block?.name, u.panchayat?.name]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(q),
    );
  }, [users, search]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const openAssign = (u: AdminUser) => {
    setAssignTarget(u);
    setAssignDistrictId(u.district_id ?? '');
    setAssignBlockId(u.block_id ?? '');
    setAssignPanchayatId(u.panchayat_id ?? '');
    setAssignError('');
  };

  const closeAssign = () => {
    setAssignTarget(null);
    setAssignError('');
  };

  const blocksForDistrict = assignDistrictId
    ? blocks.filter((b) => b.district_id === assignDistrictId)
    : blocks;
  const panchayatsForBlock = assignBlockId
    ? panchayats.filter((p) => p.block_id === assignBlockId)
    : [];

  const saveAssignment = async () => {
    if (!assignTarget || !assignPanchayatId) return;
    setIsSavingAssignment(true);
    setAssignError('');
    try {
      const { user } = await api.updateUser(assignTarget.id, { panchayat_id: Number(assignPanchayatId) });
      setUsers((prev) => prev.map((u) => (u.id === user.id ? user : u)));
      closeAssign();
    } catch (err) {
      setAssignError((err as Error).message);
    } finally {
      setIsSavingAssignment(false);
    }
  };

  const confirmDelete = async () => {
    if (!deleteTarget) return;
    setIsDeleting(true);
    setError('');
    try {
      await api.deleteUser(deleteTarget.id);
      setUsers((prev) => prev.filter((u) => u.id !== deleteTarget.id));
      setDeleteTarget(null);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsDeleting(false);
    }
  };

  const activeTab = TABS.find((t) => t.role === role)!;

  return (
    <div className="h-full flex flex-col">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2 mb-3">{error}</p>}

      <div className="flex flex-wrap gap-1.5 mb-2">
        {TABS.map((t) => (
          <button
            key={t.role}
            type="button"
            onClick={() => setRole(t.role)}
            className={`text-[11px] font-bold px-2.5 py-1 rounded-full border cursor-pointer ${
              role === t.role
                ? 'bg-sidebar text-white border-sidebar'
                : 'bg-white text-muted border-line hover:border-sidebar/40'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>
      <p className="text-[11.5px] text-muted mb-3">{activeTab.hint}</p>

      <div className="flex items-center gap-2 mb-3">
        <div className="relative max-w-sm flex-1">
          <Search className="w-3.5 h-3.5 text-muted absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={`Search ${activeTab.label.toLowerCase()}…`}
            className="w-full text-xs border border-line rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <button
          type="button"
          onClick={load}
          title="Refresh"
          disabled={isLoading}
          className="inline-flex items-center gap-1.5 text-ink border border-line bg-white hover:bg-cream text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
        <span className="text-xs text-muted ml-auto">{filtered.length} {activeTab.label.toLowerCase()}(s)</span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        {isLoading ? (
          <p className="text-sm text-muted p-6 text-center">Loading…</p>
        ) : paginated.length === 0 ? (
          <p className="text-sm text-muted p-6 text-center">
            {role === 'surveyor'
              ? 'No surveyors yet. Create one from the Surveyors page, then set a panchayat here to have them act as CPLO.'
              : 'No Gram Sachiv accounts yet. Assign the role from the Users page, then set their panchayat here.'}
          </p>
        ) : (
          <table className="w-full text-xs border-separate border-spacing-0">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-3 font-bold w-12">S.No</th>
                <th className="text-left p-3 font-bold">Name</th>
                <th className="text-left p-3 font-bold">Mobile</th>
                <th className="text-left p-3 font-bold">District</th>
                <th className="text-left p-3 font-bold">Block</th>
                <th className="text-left p-3 font-bold">Panchayat</th>
                <th className="text-left p-3 font-bold">Status</th>
                <th className="text-center p-3 font-bold w-24">Action</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((u, idx) => (
                <tr key={u.id} className={`border-t border-slate-100 ${idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'}`}>
                  <td className="p-3 text-slate-500 font-medium">{(page - 1) * PAGE_SIZE + idx + 1}</td>
                  <td className="p-3">
                    <div className="flex items-center gap-2.5">
                      <span className="w-8 h-8 rounded-full bg-sidebar text-white font-serif font-semibold text-[12px] flex items-center justify-center shrink-0">
                        {initials(u.name || u.username)}
                      </span>
                      <p className="font-semibold text-ink truncate">{u.name || u.username}</p>
                    </div>
                  </td>
                  <td className="p-3 text-slate-500">{u.mobile || '—'}</td>
                  <td className="p-3 text-slate-700">{u.district?.name || '—'}</td>
                  <td className="p-3 text-slate-700">{u.block?.name || '—'}</td>
                  <td className="p-3 text-slate-700">
                    {u.panchayat?.name || <span className="text-status-new">Not assigned</span>}
                  </td>
                  <td className="p-3">
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
                      u.is_active ? 'bg-status-closed/10 text-status-closed border-status-closed/25' : 'bg-slate-100 text-slate-500 border-slate-200'
                    }`}>
                      {u.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="p-3">
                    <div className="flex items-center justify-center gap-1.5">
                      <button
                        type="button"
                        title="Assign panchayat"
                        onClick={() => openAssign(u)}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-sidebar hover:bg-sidebar hover:text-white hover:border-sidebar cursor-pointer transition-colors"
                      >
                        <MapPin className="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        title="Delete"
                        onClick={() => setDeleteTarget(u)}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-muted hover:bg-status-rejected hover:text-white hover:border-status-rejected cursor-pointer transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length}</span>
            <div className="flex items-center gap-2">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer">
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Assign panchayat modal */}
      {assignTarget && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-6" onClick={closeAssign}>
          <div className="bg-white rounded-2xl w-full max-w-md p-6 relative" onClick={(e) => e.stopPropagation()}>
            <button onClick={closeAssign} className="absolute top-4 right-4 text-muted hover:text-ink cursor-pointer" aria-label="Close">
              <X className="w-4.5 h-4.5" />
            </button>
            <p className="font-serif font-semibold text-lg text-ink mb-1">Assign panchayat</p>
            <p className="text-[12.5px] text-muted mb-4">
              {assignTarget.name || assignTarget.username} — surveys {role === 'surveyor' ? 'submitted by' : 'verified by'} this account are scoped to this one panchayat.
            </p>

            {assignError && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2 mb-3">{assignError}</p>}

            {!masterLoaded ? (
              <p className="text-xs text-muted">Loading districts…</p>
            ) : (
              <div className="space-y-3">
                <label className="flex flex-col gap-1">
                  <span className="text-[10px] uppercase tracking-wide text-muted font-semibold">District</span>
                  <select
                    value={assignDistrictId}
                    onChange={(e) => {
                      setAssignDistrictId(e.target.value ? Number(e.target.value) : '');
                      setAssignBlockId('');
                      setAssignPanchayatId('');
                    }}
                    className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white"
                  >
                    <option value="">Select district…</option>
                    {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-[10px] uppercase tracking-wide text-muted font-semibold">Block</span>
                  <select
                    value={assignBlockId}
                    disabled={!assignDistrictId}
                    onChange={(e) => {
                      setAssignBlockId(e.target.value ? Number(e.target.value) : '');
                      setAssignPanchayatId('');
                    }}
                    className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white disabled:opacity-50"
                  >
                    <option value="">Select block…</option>
                    {blocksForDistrict.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                  </select>
                </label>
                <label className="flex flex-col gap-1">
                  <span className="text-[10px] uppercase tracking-wide text-muted font-semibold">Panchayat</span>
                  <select
                    value={assignPanchayatId}
                    disabled={!assignBlockId}
                    onChange={(e) => setAssignPanchayatId(e.target.value ? Number(e.target.value) : '')}
                    className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white disabled:opacity-50"
                  >
                    <option value="">Select panchayat…</option>
                    {panchayatsForBlock.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </label>
              </div>
            )}

            <div className="flex justify-end gap-2 mt-5">
              <button onClick={closeAssign} className="text-xs font-bold px-3.5 py-2 rounded-lg border border-line text-muted hover:bg-slate-50 cursor-pointer">
                Cancel
              </button>
              <button
                disabled={!assignPanchayatId || isSavingAssignment}
                onClick={saveAssignment}
                className="bg-sidebar hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg cursor-pointer"
              >
                {isSavingAssignment ? 'Saving…' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete confirmation */}
      {deleteTarget && (
        <div className="fixed inset-0 bg-black/40 z-[60] flex items-center justify-center p-6" onClick={() => setDeleteTarget(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm p-6" onClick={(e) => e.stopPropagation()}>
            <p className="font-serif font-semibold text-lg text-ink mb-2">Delete {activeTab.label.toLowerCase()}?</p>
            <p className="text-sm text-muted mb-6">
              Delete <b className="text-ink">{deleteTarget.name || deleteTarget.username}</b>? This permanently removes their account and cannot be undone.
            </p>
            <div className="flex justify-end gap-2">
              <button onClick={() => setDeleteTarget(null)} className="text-xs font-bold px-3.5 py-2 rounded-lg border border-line text-muted hover:bg-slate-50 cursor-pointer">
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
