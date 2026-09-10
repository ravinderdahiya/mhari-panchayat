import { useEffect, useState } from 'react';
import {
  Search, MapPin, Trash2, X, ChevronLeft, ChevronRight, RefreshCw, Eye, EyeOff,
  Pencil, Phone, Mail, IdCard, Users2, ShieldCheck,
} from 'lucide-react';
import * as api from '../services/api';
import type { MasterPagination } from '../services/api';
import type { AdminUser, Block, Department, District, Panchayat } from '../types';

const PAGE_SIZE = 10;

const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1,
  lastPage: 1,
  perPage: PAGE_SIZE,
  total: 0,
  from: null,
  to: null,
};

// This tab covers both the imported `cplo` role (one per Gram Panchayat,
// already panchayat-scoped from ImportHaryanaOfficials) and any `surveyor`
// who has been given a single panchayat to act as CPLO - restricting them
// (via the existing department-assignment scoping) to Panchayati Raj asset
// surveys for that panchayat. Most plain surveyors won't have a panchayat
// set at all.
const TABS = [
  { roles: ['cplo', 'surveyor'], label: 'Surveyor (CPLO)', hint: 'CPLOs and Surveyors acting as CPLO - scoped to Panchayati Raj surveys for their assigned panchayat only.' },
  { roles: ['gram_sachiv'], label: 'Gram Sachiv', hint: 'Verifies (approves/rejects) surveys submitted for their assigned panchayat.' },
] as const;

function initials(name: string) {
  return name.split(' ').filter(Boolean).slice(0, 2).map((n) => n[0]!.toUpperCase()).join('') || '?';
}

function roleLabel(role: string) {
  return role.replace(/_/g, ' ');
}

export default function CploManagementPage() {
  const [activeLabel, setActiveLabel] = useState<(typeof TABS)[number]['label']>(TABS[0].label);
  const activeTab = TABS.find((t) => t.label === activeLabel)!;
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [search, setSearch] = useState('');
  const [districtFilter, setDistrictFilter] = useState('All');
  const [blockFilter, setBlockFilter] = useState('All');
  const [panchayatFilter, setPanchayatFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState<'All' | 'Active' | 'Inactive'>('All');
  const [page, setPage] = useState(1);
  const [refreshKey, setRefreshKey] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const [districts, setDistricts] = useState<District[]>([]);
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [panchayats, setPanchayats] = useState<Panchayat[]>([]);
  const [panchayatsLoaded, setPanchayatsLoaded] = useState(false);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [roles, setRoles] = useState<string[]>([]);
  const [roleFullNames, setRoleFullNames] = useState<Record<string, string>>({});

  const [assignTarget, setAssignTarget] = useState<AdminUser | null>(null);
  const [assignDistrictId, setAssignDistrictId] = useState<number | ''>('');
  const [assignBlockId, setAssignBlockId] = useState<number | ''>('');
  const [assignPanchayatId, setAssignPanchayatId] = useState<number | ''>('');
  const [isSavingAssignment, setIsSavingAssignment] = useState(false);
  const [assignError, setAssignError] = useState('');

  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const [hiddenPasswordIds, setHiddenPasswordIds] = useState<Set<number>>(new Set());

  const [viewTarget, setViewTarget] = useState<AdminUser | null>(null);
  const [selected, setSelected] = useState<AdminUser | null>(null);
  const [editName, setEditName] = useState('');
  const [editMobile, setEditMobile] = useState('');
  const [editEmail, setEditEmail] = useState('');
  const [editEmployeeId, setEditEmployeeId] = useState('');
  const [editMemberId, setEditMemberId] = useState('');
  const [editFamilyId, setEditFamilyId] = useState('');
  const [editRole, setEditRole] = useState('');
  const [editDepartment, setEditDepartment] = useState('');
  const [editDistrict, setEditDistrict] = useState('');
  const [editBlock, setEditBlock] = useState('');
  const [editPanchayat, setEditPanchayat] = useState('');
  const [editActive, setEditActive] = useState(true);
  const [editPassword, setEditPassword] = useState('');
  const [showEditPassword, setShowEditPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [editError, setEditError] = useState('');

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);

    const timer = window.setTimeout(() => {
      api.getUsers({
        page,
        perPage: PAGE_SIZE,
        q: search,
        role: activeTab.roles.join(','),
        districtId: districtFilter === 'All' ? undefined : Number(districtFilter),
        blockId: blockFilter === 'All' ? undefined : Number(blockFilter),
        panchayatId: panchayatFilter === 'All' ? undefined : Number(panchayatFilter),
        status: statusFilter === 'All' ? 'all' : statusFilter === 'Active' ? 'active' : 'inactive',
      })
        .then(({ users: fetched, pagination: meta }) => {
          if (cancelled) return;
          setUsers(fetched);
          if (meta) setPagination(meta);
          setError('');
        })
        .catch((err) => {
          if (!cancelled) setError((err as Error).message);
        })
        .finally(() => {
          if (!cancelled) setIsLoading(false);
        });
    }, 250);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [activeLabel, page, search, districtFilter, blockFilter, panchayatFilter, statusFilter, refreshKey]);

  useEffect(() => { setPage(1); setSearch(''); }, [activeLabel]);

  // Districts/blocks are small lists, safe to fetch on mount for the filter
  // bar. Panchayats (6000+) are lazy-loaded on first actual need - either
  // narrowing the filters to a block, or opening the assign-panchayat modal.
  useEffect(() => {
    api.masterApi('districts').list().then(({ items }) => setDistricts(items || [])).catch(() => {});
    api.masterApi('blocks').list().then(({ items }) => setBlocks(items || [])).catch(() => {});
    api.masterApi('departments').list().then(({ items }) => setDepartments(items || [])).catch(() => {});
    api.masterApi('roles').list().then(({ items }) => {
      const list = (items || []) as { name: string; full_name?: string | null }[];
      setRoles(list.map((item) => item.name));
      setRoleFullNames(Object.fromEntries(list.filter((item) => item.full_name).map((item) => [item.name, item.full_name as string])));
    }).catch(() => {});
  }, []);

  const loadPanchayatsOnce = () => {
    if (panchayatsLoaded) return;
    setPanchayatsLoaded(true);
    api.masterApi('panchayats').list().then(({ items }) => setPanchayats(items || [])).catch(() => {});
  };

  const filterBlocks = districtFilter === 'All' ? blocks : blocks.filter((b) => String(b.district_id) === districtFilter);
  const filterPanchayats = blockFilter === 'All' ? [] : panchayats.filter((p) => String(p.block_id) === blockFilter);

  const openAssign = (u: AdminUser) => {
    loadPanchayatsOnce();
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

  const editBlocksForDistrict = editDistrict ? blocks.filter((b) => String(b.district_id) === editDistrict) : blocks;
  const editPanchayatsForBlock = editBlock ? panchayats.filter((p) => String(p.block_id) === editBlock) : [];

  const selectUser = (u: AdminUser) => {
    loadPanchayatsOnce();
    setSelected(u);
    setEditName(u.name ?? '');
    setEditMobile(u.mobile ?? '');
    setEditEmail(u.email ?? '');
    setEditEmployeeId(u.employee_id ?? '');
    setEditMemberId(u.member_id ?? '');
    setEditFamilyId(u.family_id ?? '');
    setEditRole(u.role);
    setEditDepartment(u.department_id ? String(u.department_id) : '');
    setEditDistrict(u.district_id ? String(u.district_id) : '');
    setEditBlock(u.block_id ? String(u.block_id) : '');
    setEditPanchayat(u.panchayat_id ? String(u.panchayat_id) : '');
    setEditActive(u.is_active);
    setEditPassword('');
    setShowEditPassword(false);
    setEditError('');
  };

  const closeEdit = () => {
    setSelected(null);
    setEditError('');
  };

  const saveEdit = async () => {
    if (!selected) return;
    setIsSubmitting(true);
    setEditError('');
    try {
      const payload: Parameters<typeof api.updateUser>[1] = {
        name: editName.trim() || null,
        mobile: editMobile.trim() || null,
        email: editEmail.trim() || null,
        employee_id: editEmployeeId.trim() || null,
        member_id: editMemberId.trim() || null,
        family_id: editFamilyId.trim() || null,
        role: editRole,
        department_id: editDepartment ? Number(editDepartment) : null,
        is_active: editActive,
      };
      if (editPassword.trim()) {
        payload.password = editPassword.trim();
      }

      // Same panchayat-wins-over-block/district rule as the Users page: only
      // send panchayat_id for roles that actually have (or are losing) one,
      // otherwise a manually-picked block/district would get wiped out.
      const newPanchayatId = editPanchayat ? Number(editPanchayat) : null;
      if (newPanchayatId !== null || selected.panchayat_id !== null) {
        payload.panchayat_id = newPanchayatId;
      } else {
        payload.district_id = editDistrict ? Number(editDistrict) : null;
        payload.block_id = editBlock ? Number(editBlock) : null;
      }

      const { user } = await api.updateUser(selected.id, payload);
      setUsers((prev) => prev.map((u) => (u.id === user.id ? user : u)));
      closeEdit();
    } catch (err) {
      setEditError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const confirmDelete = async () => {
    if (!deleteTarget) return;
    setIsDeleting(true);
    setError('');
    try {
      await api.deleteUser(deleteTarget.id);
      setDeleteTarget(null);
      if (users.length === 1 && page > 1) {
        setPage((current) => current - 1);
      } else {
        setRefreshKey((k) => k + 1);
      }
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className="h-full flex flex-col">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2 mb-3">{error}</p>}

      <div className="flex flex-wrap gap-1.5 mb-2">
        {TABS.map((t) => (
          <button
            key={t.label}
            type="button"
            onClick={() => setActiveLabel(t.label)}
            className={`text-[11px] font-bold px-2.5 py-1 rounded-full border cursor-pointer ${
              activeLabel === t.label
                ? 'bg-sidebar text-white border-sidebar'
                : 'bg-white text-muted border-line hover:border-sidebar/40'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>
      <p className="text-[11.5px] text-muted mb-3">{activeTab.hint}</p>

      <div className="flex flex-wrap items-center gap-2 mb-3">
        <div className="relative min-w-[200px] max-w-sm flex-1">
          <Search className="w-3.5 h-3.5 text-muted absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
            placeholder={`Search ${activeTab.label.toLowerCase()}…`}
            className="w-full text-xs border border-line rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select
          value={districtFilter}
          onChange={(e) => {
            setDistrictFilter(e.target.value);
            setBlockFilter('All');
            setPanchayatFilter('All');
            setPage(1);
          }}
          className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Districts</option>
          {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select
          value={blockFilter}
          onChange={(e) => {
            const next = e.target.value;
            setBlockFilter(next);
            setPanchayatFilter('All');
            setPage(1);
            if (next !== 'All') loadPanchayatsOnce();
          }}
          className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Blocks</option>
          {filterBlocks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
        <select
          value={panchayatFilter}
          onChange={(e) => { setPanchayatFilter(e.target.value); setPage(1); }}
          disabled={blockFilter === 'All'}
          title={blockFilter === 'All' ? 'Select a block first' : undefined}
          className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white disabled:opacity-50"
        >
          <option value="All">All Panchayats</option>
          {filterPanchayats.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <select
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value as 'All' | 'Active' | 'Inactive'); setPage(1); }}
          className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Statuses</option>
          <option value="Active">Active</option>
          <option value="Inactive">Inactive</option>
        </select>
        <button
          type="button"
          onClick={() => setRefreshKey((k) => k + 1)}
          title="Refresh"
          disabled={isLoading}
          className="inline-flex items-center gap-1.5 text-ink border border-line bg-white hover:bg-cream text-xs font-bold px-3.5 py-2 rounded-lg cursor-pointer disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
        <span className="text-xs text-muted ml-auto">{pagination.total} {activeTab.label.toLowerCase()}(s)</span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden flex-1 min-h-0 flex flex-col">
        {isLoading ? (
          <p className="text-sm text-muted p-6 text-center">Loading…</p>
        ) : users.length === 0 ? (
          <p className="text-sm text-muted p-6 text-center">
            {activeLabel === TABS[0].label
              ? 'No CPLOs or surveyors match your filters. Assign the cplo/surveyor role from the Users page, then set a panchayat here to have them act as CPLO.'
              : 'No Gram Sachiv accounts match your filters. Assign the role from the Users page, then set their panchayat here.'}
          </p>
        ) : (
          <div className="flex-1 min-h-0 overflow-auto">
            <table className="w-full text-xs border-separate border-spacing-0">
              <thead className="sticky top-0 z-10">
                <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                  <th className="text-left p-3 font-bold w-12">S.No</th>
                  <th className="text-left p-3 font-bold">Username</th>
                  <th className="text-left p-3 font-bold">Password</th>
                  <th className="text-left p-3 font-bold">Phone No.</th>
                  <th className="text-left p-3 font-bold">Name</th>
                  <th className="text-left p-3 font-bold">Email</th>
                  <th className="text-left p-3 font-bold">Role</th>
                  <th className="text-left p-3 font-bold">Department</th>
                  <th className="text-left p-3 font-bold">District</th>
                  <th className="text-left p-3 font-bold">Block</th>
                  <th className="text-left p-3 font-bold">Panchayat</th>
                  <th className="text-left p-3 font-bold">Member ID</th>
                  <th className="text-left p-3 font-bold">Family ID</th>
                  <th className="text-left p-3 font-bold">Status</th>
                  <th className="text-left p-3 font-bold">Joined</th>
                  <th className="text-center p-3 font-bold w-44">Action</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u, idx) => (
                  <tr
                    key={u.id}
                    onClick={() => setViewTarget(u)}
                    className={`border-t border-slate-100 cursor-pointer hover:bg-accent/10 ${idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'}`}
                  >
                    <td className="p-3 text-slate-500 font-medium">{(pagination.currentPage - 1) * PAGE_SIZE + idx + 1}</td>
                    <td className="p-3">
                      <div className="flex items-center gap-2.5">
                        <span className="w-8 h-8 rounded-full bg-sidebar text-white font-serif font-semibold text-[12px] flex items-center justify-center shrink-0">
                          {initials(u.name || u.username)}
                        </span>
                        <p className="font-semibold text-ink truncate">{u.username}</p>
                      </div>
                    </td>
                    <td className="p-3" onClick={(e) => e.stopPropagation()}>
                      {u.login_password ? (
                        <div className="flex items-center gap-1.5 min-w-[110px]">
                          <span className="font-mono text-[11px] text-slate-800">
                            {hiddenPasswordIds.has(u.id) ? '••••••••' : u.login_password}
                          </span>
                          <button
                            type="button"
                            onClick={() => setHiddenPasswordIds((prev) => {
                              const next = new Set(prev);
                              if (next.has(u.id)) next.delete(u.id);
                              else next.add(u.id);
                              return next;
                            })}
                            className="p-1 rounded-md text-slate-400 hover:bg-slate-100 hover:text-slate-600 cursor-pointer"
                            title={hiddenPasswordIds.has(u.id) ? 'Show password' : 'Hide password'}
                          >
                            {hiddenPasswordIds.has(u.id) ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                          </button>
                        </div>
                      ) : '—'}
                    </td>
                    <td className="p-3 text-slate-500">{u.mobile || '—'}</td>
                    <td className="p-3 text-slate-600">{u.name || '—'}</td>
                    <td className="p-3 text-slate-500">{u.email || '—'}</td>
                    <td className="p-3">
                      <span
                        title={roleFullNames[u.role]}
                        className="text-[10px] font-bold uppercase px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200"
                      >
                        {roleLabel(u.role)}
                      </span>
                    </td>
                    <td className="p-3 text-slate-500">{u.department?.name || '—'}</td>
                    <td className="p-3 text-slate-700">{u.district?.name || '—'}</td>
                    <td className="p-3 text-slate-700">{u.block?.name || '—'}</td>
                    <td className="p-3 text-slate-700">
                      {u.panchayat?.name || <span className="text-status-new">Not assigned</span>}
                    </td>
                    <td className="p-3 text-slate-500">{u.member_id || '—'}</td>
                    <td className="p-3 text-slate-500">{u.family_id || '—'}</td>
                    <td className="p-3">
                      <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
                        u.is_active ? 'bg-status-closed/10 text-status-closed border-status-closed/25' : 'bg-slate-100 text-slate-500 border-slate-200'
                      }`}>
                        {u.is_active ? 'Active' : 'Inactive'}
                      </span>
                    </td>
                    <td className="p-3 text-slate-400">{new Date(u.created_at).toLocaleDateString()}</td>
                    <td className="p-3" onClick={(e) => e.stopPropagation()}>
                      <div className="flex items-center justify-center gap-1.5">
                        <button
                          type="button"
                          title="View"
                          onClick={() => setViewTarget(u)}
                          className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-muted hover:bg-slate-100 cursor-pointer transition-colors"
                        >
                          <Eye className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          title="Edit"
                          onClick={() => selectUser(u)}
                          className="inline-flex items-center justify-center w-8 h-8 rounded-lg border border-line text-muted hover:bg-slate-100 cursor-pointer transition-colors"
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </button>
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
          </div>
        )}

        {pagination.total > 0 && (
          <div className="shrink-0 flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {pagination.from ?? 0}–{pagination.to ?? 0} of {pagination.total}</span>
            <div className="flex items-center gap-2">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {pagination.currentPage} of {pagination.lastPage}</span>
              <button onClick={() => setPage((p) => Math.min(pagination.lastPage, p + 1))} disabled={page === pagination.lastPage} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40 cursor-pointer">
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
              {assignTarget.name || assignTarget.username} — surveys {activeLabel === TABS[0].label ? 'submitted by' : 'verified by'} this account are scoped to this one panchayat.
            </p>

            {assignError && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2 mb-3">{assignError}</p>}

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
                  disabled={!assignBlockId || !panchayatsLoaded}
                  onChange={(e) => setAssignPanchayatId(e.target.value ? Number(e.target.value) : '')}
                  className="text-xs border border-line rounded-lg px-2.5 py-2 bg-white disabled:opacity-50"
                >
                  <option value="">{!panchayatsLoaded ? 'Loading panchayats…' : 'Select panchayat…'}</option>
                  {panchayatsForBlock.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </label>
            </div>

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

      {/* View details modal */}
      {viewTarget && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 p-5 overflow-y-auto"
          onClick={() => setViewTarget(null)}
        >
          <div
            className="w-full max-w-lg my-auto bg-white rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="relative bg-gradient-to-br from-sidebar to-sidebar/80 px-5 pt-5 pb-6 text-white">
              <button
                type="button"
                onClick={() => setViewTarget(null)}
                className="absolute top-3 right-3 p-1.5 rounded-lg text-white/80 hover:bg-white/15 hover:text-white cursor-pointer"
              >
                <X className="w-4 h-4" />
              </button>
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-full bg-white/15 border border-white/25 flex items-center justify-center font-bold text-sm">
                  {initials(viewTarget.name || viewTarget.username)}
                </div>
                <div className="min-w-0">
                  <h2 className="font-bold text-base leading-tight truncate">{viewTarget.name || viewTarget.username}</h2>
                  <p className="text-xs text-white/75">@{viewTarget.username}</p>
                </div>
                <span className="ml-auto shrink-0 text-[10px] font-bold uppercase px-2.5 py-1 rounded-full bg-white/15 border border-white/25">
                  {roleLabel(viewTarget.role)}
                </span>
              </div>
              {roleFullNames[viewTarget.role] && (
                <p className="mt-2 text-[11.5px] text-white/85">{roleFullNames[viewTarget.role]}</p>
              )}
            </div>

            <div className="p-5 space-y-4">
              <ViewSection title="Contact" icon={<Phone className="w-3.5 h-3.5" />}>
                <ViewField label="Phone No." value={viewTarget.mobile} />
                <ViewField label="Email" value={viewTarget.email} />
              </ViewSection>

              <ViewSection title="Jurisdiction" icon={<MapPin className="w-3.5 h-3.5" />}>
                <ViewField label="Department" value={viewTarget.department?.name} />
                <ViewField label="District" value={viewTarget.district?.name} />
                <ViewField label="Block" value={viewTarget.block?.name} />
                <ViewField label="Panchayat" value={viewTarget.panchayat?.name} />
              </ViewSection>

              <ViewSection title="Identifiers" icon={<IdCard className="w-3.5 h-3.5" />}>
                <ViewField label="Employee ID" value={viewTarget.employee_id} />
                <ViewField label="Member ID" value={viewTarget.member_id} />
                <ViewField label="Family ID" value={viewTarget.family_id} />
              </ViewSection>

              <ViewSection title="Account" icon={<ShieldCheck className="w-3.5 h-3.5" />}>
                <ViewField label="Password" value={viewTarget.login_password} mono />
                <ViewField
                  label="Status"
                  value={viewTarget.is_active ? 'Active' : 'Inactive'}
                  badge={viewTarget.is_active ? 'emerald' : 'slate'}
                />
                <ViewField label="Registration" value={viewTarget.registration_status} />
                <ViewField label="Joined" value={new Date(viewTarget.created_at).toLocaleDateString()} />
              </ViewSection>
            </div>

            <div className="flex items-center gap-2 px-5 pb-5">
              <button
                type="button"
                onClick={() => {
                  const u = viewTarget;
                  setViewTarget(null);
                  selectUser(u);
                }}
                className="inline-flex items-center gap-1.5 bg-sidebar hover:opacity-90 text-white text-xs font-bold px-4 py-2 rounded-lg cursor-pointer"
              >
                <Pencil className="w-3.5 h-3.5" />
                Edit
              </button>
              <button
                type="button"
                onClick={() => setViewTarget(null)}
                className="text-xs font-bold px-4 py-2 rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50 cursor-pointer"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Edit modal */}
      {selected && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 p-5 overflow-y-auto"
          onClick={closeEdit}
        >
          <div
            className="w-full max-w-3xl my-auto bg-white rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="relative bg-gradient-to-br from-sidebar to-sidebar/80 px-5 pt-5 pb-6 text-white">
              <button
                type="button"
                onClick={closeEdit}
                className="absolute top-3 right-3 p-1.5 rounded-lg text-white/80 hover:bg-white/15 hover:text-white cursor-pointer"
              >
                <X className="w-4 h-4" />
              </button>
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-full bg-white/15 border border-white/25 flex items-center justify-center font-bold text-sm">
                  {initials(selected.name || selected.username)}
                </div>
                <div className="min-w-0">
                  <h2 className="font-bold text-base leading-tight truncate">{selected.name || selected.username}</h2>
                  <p className="text-xs text-white/75">@{selected.username} {selected.email && `· ${selected.email}`}</p>
                </div>
              </div>
            </div>

            <div className="p-5 space-y-5 max-h-[70vh] overflow-y-auto">
              {editError && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{editError}</p>}

              <EditSection title="Identity" icon={<Users2 className="w-3.5 h-3.5" />}>
                <TextField label="Full Name" value={editName} onChange={setEditName} span={2} />
                <TextField label="Phone No." value={editMobile} onChange={setEditMobile} icon={<Phone className="w-3.5 h-3.5" />} />
                <TextField label="Email" value={editEmail} onChange={setEditEmail} icon={<Mail className="w-3.5 h-3.5" />} />
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Password</label>
                  <div className="relative">
                    <input
                      type={showEditPassword ? 'text' : 'password'}
                      value={editPassword}
                      onChange={(e) => setEditPassword(e.target.value)}
                      placeholder={selected.login_password ? 'Leave blank to keep current' : 'Set a password to show it here'}
                      autoComplete="new-password"
                      className="w-full text-xs border border-line rounded-lg py-1.5 pl-2.5 pr-8 focus:outline-none focus:ring-2 focus:ring-accent"
                    />
                    <button
                      type="button"
                      onClick={() => setShowEditPassword((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-muted hover:text-ink cursor-pointer"
                      title={showEditPassword ? 'Hide password' : 'Show password'}
                    >
                      {showEditPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  {selected.login_password && !editPassword && (
                    <p className="mt-1 font-mono text-[11px] text-muted">Current: {selected.login_password}</p>
                  )}
                </div>
              </EditSection>

              <EditSection title="Identifiers" icon={<IdCard className="w-3.5 h-3.5" />}>
                <TextField label="Employee ID" value={editEmployeeId} onChange={setEditEmployeeId} />
                <TextField label="Member ID" value={editMemberId} onChange={setEditMemberId} />
                <TextField label="Family ID" value={editFamilyId} onChange={setEditFamilyId} />
              </EditSection>

              <EditSection title="Role & Access" icon={<ShieldCheck className="w-3.5 h-3.5" />}>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Role</label>
                  <select
                    value={editRole}
                    onChange={(e) => setEditRole(e.target.value)}
                    className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    {(editRole && !roles.includes(editRole) ? [...roles, editRole] : roles).map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}
                  </select>
                  {roleFullNames[editRole] && (
                    <p className="mt-1 text-[11px] text-muted">{roleFullNames[editRole]}</p>
                  )}
                </div>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Department</label>
                  <select
                    value={editDepartment}
                    onChange={(e) => setEditDepartment(e.target.value)}
                    className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Status</label>
                  <label className="flex items-center gap-2 text-xs font-semibold px-2.5 py-[7px] border border-line rounded-lg text-ink">
                    <input
                      type="checkbox"
                      checked={editActive}
                      onChange={(e) => setEditActive(e.target.checked)}
                      className="accent-sidebar"
                    />
                    Active
                  </label>
                </div>
              </EditSection>

              <EditSection title="Jurisdiction" icon={<MapPin className="w-3.5 h-3.5" />}>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">District</label>
                  <select
                    value={editDistrict}
                    onChange={(e) => {
                      setEditDistrict(e.target.value);
                      setEditBlock('');
                      setEditPanchayat('');
                    }}
                    className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Block</label>
                  <select
                    value={editBlock}
                    onChange={(e) => {
                      setEditBlock(e.target.value);
                      setEditPanchayat('');
                    }}
                    disabled={!editDistrict}
                    className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-muted focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {editBlocksForDistrict.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-muted uppercase block mb-1">Panchayat</label>
                  <select
                    value={editPanchayat}
                    onChange={(e) => setEditPanchayat(e.target.value)}
                    disabled={!editBlock || !panchayatsLoaded}
                    className="w-full text-xs border border-line rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-muted focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">{!panchayatsLoaded ? 'Loading…' : '— none —'}</option>
                    {editPanchayatsForBlock.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </div>
              </EditSection>
            </div>

            <div className="flex items-center gap-2 px-5 py-4 border-t border-slate-100 bg-slate-50">
              <button
                disabled={isSubmitting}
                onClick={saveEdit}
                className="bg-sidebar hover:opacity-90 disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg cursor-pointer"
              >
                {isSubmitting ? 'Saving…' : 'Save Changes'}
              </button>
              <button
                type="button"
                onClick={closeEdit}
                className="text-xs font-bold px-4 py-2 rounded-lg border border-slate-200 text-slate-600 hover:bg-white cursor-pointer"
              >
                Close
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

function ViewSection({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <p className="flex items-center gap-1.5 text-[10px] font-bold text-muted uppercase tracking-wide mb-2">
        {icon} {title}
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs bg-cream border border-line rounded-xl p-3">
        {children}
      </div>
    </div>
  );
}

function ViewField({ label, value, badge, mono }: { label: string; value?: string | null; badge?: 'emerald' | 'slate'; mono?: boolean }) {
  return (
    <div>
      <p className="text-[10px] font-bold text-muted uppercase mb-0.5">{label}</p>
      {badge ? (
        <span className={`inline-block text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
          badge === 'emerald' ? 'bg-status-closed/10 text-status-closed border-status-closed/25' : 'bg-slate-100 text-slate-500 border-slate-200'
        }`}>
          {value || '—'}
        </span>
      ) : (
        <p className={`text-ink font-medium ${mono ? 'font-mono text-[11px]' : ''}`}>{value || '—'}</p>
      )}
    </div>
  );
}

function EditSection({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <p className="flex items-center gap-1.5 text-[10px] font-bold text-muted uppercase tracking-wide mb-2">
        {icon} {title}
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {children}
      </div>
    </div>
  );
}

function TextField({ label, value, onChange, icon, span }: {
  label: string; value: string; onChange: (value: string) => void; icon?: React.ReactNode; span?: 2 | 3;
}) {
  return (
    <div className={span === 2 ? 'sm:col-span-2' : span === 3 ? 'sm:col-span-3' : undefined}>
      <label className="text-[10px] font-bold text-muted uppercase block mb-1">{label}</label>
      <div className="relative">
        {icon && <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted">{icon}</span>}
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className={`w-full text-xs border border-line rounded-lg py-1.5 focus:outline-none focus:ring-2 focus:ring-accent ${icon ? 'pl-8 pr-2.5' : 'px-2.5'}`}
        />
      </div>
    </div>
  );
}
