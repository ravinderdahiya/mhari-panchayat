import { useEffect, useMemo, useState } from 'react';
import {
  Search, Users as UsersIcon, Inbox, ChevronLeft, ChevronRight, Lock, Trash2, Eye, EyeOff, Pencil,
  Phone, Mail, MapPin, IdCard, Users2, ShieldCheck, X, RefreshCw,
} from 'lucide-react';
import * as api from '../services/api';
import { masterApi } from '../services/api';
import type { MasterPagination } from '../services/api';
import type { AdminUser, Block, Department, District, Panchayat, User } from '../types';

interface UsersPageProps {
  currentUser: User;
}

const PAGE_SIZE = 10;

const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1,
  lastPage: 1,
  perPage: PAGE_SIZE,
  total: 0,
  from: null,
  to: null,
};

function roleLabel(role: string) {
  return role.replace(/_/g, ' ');
}

function initials(name: string | null, username: string) {
  const source = (name || username).trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return (parts[0][0] + (parts[1]?.[0] ?? '')).toUpperCase();
}

const AVATAR_PALETTE = [
  'bg-rose-100 text-rose-700', 'bg-amber-100 text-amber-700', 'bg-emerald-100 text-emerald-700',
  'bg-sky-100 text-sky-700', 'bg-violet-100 text-violet-700', 'bg-orange-100 text-orange-700',
];

function avatarColor(id: number) {
  return AVATAR_PALETTE[id % AVATAR_PALETTE.length];
}

export default function UsersPage({ currentUser }: UsersPageProps) {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [districts, setDistricts] = useState<District[]>([]);
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [panchayats, setPanchayats] = useState<Panchayat[]>([]);
  const [panchayatsLoaded, setPanchayatsLoaded] = useState(false);
  const [roles, setRoles] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('All');
  const [districtFilter, setDistrictFilter] = useState('All');
  const [blockFilter, setBlockFilter] = useState('All');
  const [panchayatFilter, setPanchayatFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState<'All' | 'Active' | 'Inactive'>('All');
  const [page, setPage] = useState(1);
  const [refreshKey, setRefreshKey] = useState(0);
  const [selected, setSelected] = useState<AdminUser | null>(null);
  const [viewTarget, setViewTarget] = useState<AdminUser | null>(null);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

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
  const [hiddenPasswordIds, setHiddenPasswordIds] = useState<Set<number>>(new Set());

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);

    const timer = window.setTimeout(() => {
      api.getUsers({
        page,
        perPage: PAGE_SIZE,
        q: searchQuery,
        role: roleFilter,
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
  }, [page, searchQuery, roleFilter, districtFilter, blockFilter, panchayatFilter, statusFilter, refreshKey]);

  useEffect(() => {
    masterApi('departments').list().then(({ items }) => setDepartments(items)).catch(() => {});
    masterApi('districts').list().then(({ items }) => setDistricts(items)).catch(() => {});
    masterApi('blocks').list().then(({ items }) => setBlocks(items)).catch(() => {});
    masterApi('roles').list().then(({ items }) => {
      setRoles(items.map((item: { name: string }) => item.name));
    }).catch(() => {});
  }, []);

  // Panchayats (6000+) are only fetched once someone actually opens the edit
  // form and needs the dropdown, not on every page load.
  const loadPanchayatsOnce = () => {
    if (panchayatsLoaded) return;
    setPanchayatsLoaded(true);
    masterApi('panchayats').list().then(({ items }) => setPanchayats(items)).catch(() => {});
  };

  const blocksForDistrict = useMemo(
    () => blocks.filter((b) => String(b.district_id) === editDistrict),
    [blocks, editDistrict],
  );
  const panchayatsForBlock = useMemo(
    () => panchayats.filter((p) => String(p.block_id) === editBlock),
    [panchayats, editBlock],
  );
  const filterBlocks = useMemo(
    () => (districtFilter === 'All' ? blocks : blocks.filter((b) => String(b.district_id) === districtFilter)),
    [blocks, districtFilter],
  );
  const filterPanchayats = useMemo(
    () => (blockFilter === 'All' ? [] : panchayats.filter((p) => String(p.block_id) === blockFilter)),
    [panchayats, blockFilter],
  );

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
    setError('');
  };

  const isSelf = selected?.id === currentUser.id;

  const save = async () => {
    if (!selected) return;
    setIsSubmitting(true);
    setError('');
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

      // The backend derives block/district FROM panchayat whenever
      // panchayat_id is present in the request (even as null) - only send it
      // for roles that actually have (or are losing) a panchayat, otherwise
      // a BDPO/DDPO's manually-picked block/district would get wiped out.
      const newPanchayatId = editPanchayat ? Number(editPanchayat) : null;
      if (newPanchayatId !== null || selected.panchayat_id !== null) {
        payload.panchayat_id = newPanchayatId;
      } else {
        payload.district_id = editDistrict ? Number(editDistrict) : null;
        payload.block_id = editBlock ? Number(editBlock) : null;
      }

      const { user } = await api.updateUser(selected.id, payload);
      setSelected(user);
      setEditPassword('');
      setShowEditPassword(false);
      setRefreshKey((k) => k + 1);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const removeUser = async () => {
    if (!deleteTarget || deleteTarget.id === currentUser.id) return;
    setIsDeleting(true);
    setError('');
    setSuccessMessage('');
    try {
      const { message } = await api.deleteUser(deleteTarget.id);
      if (selected?.id === deleteTarget.id) setSelected(null);
      setSuccessMessage(message || 'User deleted successfully');
      setDeleteTarget(null);
      if (users.length === 1 && page > 1) {
        setPage((current) => current - 1);
      } else {
        setRefreshKey((k) => k + 1);
      }
    } catch (err) {
      setError((err as Error).message);
      setDeleteTarget(null);
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className="space-y-4">
      {successMessage && (
        <div role="alert" className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">
          {successMessage}
        </div>
      )}
      {error && !selected && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
          {error}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={searchQuery}
            onChange={(e) => { setSearchQuery(e.target.value); setPage(1); }}
            placeholder="Search users…"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setPage(1); }} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Roles</option>
          {roles.map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}
        </select>
        <select
          value={districtFilter}
          onChange={(e) => {
            setDistrictFilter(e.target.value);
            setBlockFilter('All');
            setPanchayatFilter('All');
            setPage(1);
          }}
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
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
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Blocks</option>
          {filterBlocks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
        <select
          value={panchayatFilter}
          onChange={(e) => { setPanchayatFilter(e.target.value); setPage(1); }}
          disabled={blockFilter === 'All'}
          title={blockFilter === 'All' ? 'Select a block first' : undefined}
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white disabled:bg-slate-50 disabled:text-slate-400"
        >
          <option value="All">All Panchayats</option>
          {filterPanchayats.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value as any); setPage(1); }} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Statuses</option>
          <option value="Active">Active</option>
          <option value="Inactive">Inactive</option>
        </select>
        <button
          type="button"
          onClick={() => setRefreshKey((k) => k + 1)}
          title="Refresh"
          disabled={isLoading}
          className="inline-flex items-center gap-1.5 text-xs font-bold text-slate-700 border border-slate-300 bg-white hover:bg-slate-50 px-3 py-2 rounded-lg cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
        <span className="text-xs text-slate-400 ml-auto flex items-center gap-1.5">
          <UsersIcon className="w-3.5 h-3.5" />
          {pagination.total} users
        </span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        {isLoading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : users.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No users match your filters.</p>
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-2.5">S.No.</th>
                <th className="text-left p-2.5">Username</th>
                <th className="text-left p-2.5">Password</th>
                <th className="text-left p-2.5">Phone No.</th>
                <th className="text-left p-2.5">Name</th>
                <th className="text-left p-2.5">Email</th>
                <th className="text-left p-2.5">Role</th>
                <th className="text-left p-2.5">Department</th>
                <th className="text-left p-2.5">District</th>
                <th className="text-left p-2.5">Block</th>
                <th className="text-left p-2.5">Panchayat</th>
                <th className="text-left p-2.5">Member ID</th>
                <th className="text-left p-2.5">Family ID</th>
                <th className="text-left p-2.5">Status</th>
                <th className="text-left p-2.5">Joined</th>
                <th className="text-right p-2.5">Action</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u, index) => (
                <tr
                  key={u.id}
                  onClick={() => setViewTarget(u)}
                  className={`border-t border-slate-100 cursor-pointer hover:bg-slate-50 ${selected?.id === u.id ? 'bg-accent/10' : ''}`}
                >
                  <td className="p-2.5 text-slate-400">{(page - 1) * PAGE_SIZE + index + 1}</td>
                  <td className="p-2.5 font-semibold text-slate-800">
                    {u.username}
                    {u.id === currentUser.id && <span className="ml-1.5 text-[9px] text-slate-400">(you)</span>}
                  </td>
                  <td className="p-2.5" onClick={(event) => event.stopPropagation()}>
                    <PasswordReveal
                      password={u.login_password}
                      hidden={hiddenPasswordIds.has(u.id)}
                      onToggle={() => setHiddenPasswordIds((prev) => {
                        const next = new Set(prev);
                        if (next.has(u.id)) next.delete(u.id);
                        else next.add(u.id);
                        return next;
                      })}
                      onSet={() => selectUser(u)}
                    />
                  </td>
                  <td className="p-2.5 text-slate-500">{u.mobile || '—'}</td>
                  <td className="p-2.5 text-slate-600">{u.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.email || '—'}</td>
                  <td className="p-2.5">
                    <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                      {roleLabel(u.role)}
                    </span>
                  </td>
                  <td className="p-2.5 text-slate-500">{u.department?.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.district?.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.block?.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.panchayat?.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.member_id || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.family_id || '—'}</td>
                  <td className="p-2.5">
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
                      u.is_active ? 'bg-status-closed/10 text-status-closed border-status-closed/25' : 'bg-slate-100 text-slate-500 border-slate-200'
                    }`}>
                      {u.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="p-2.5 text-slate-400">{new Date(u.created_at).toLocaleDateString()}</td>
                  <td className="p-2.5" onClick={(event) => event.stopPropagation()}>
                    <div className="flex items-center justify-end gap-1">
                      <button
                        type="button"
                        onClick={() => setViewTarget(u)}
                        title={`View ${u.name || u.username}`}
                        aria-label={`View ${u.name || u.username}`}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-lg text-slate-500 hover:bg-slate-100"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                      <button
                        type="button"
                        onClick={() => selectUser(u)}
                        title={`Edit ${u.name || u.username}`}
                        aria-label={`Edit ${u.name || u.username}`}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-lg text-slate-500 hover:bg-slate-100"
                      >
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button
                        type="button"
                        disabled={u.id === currentUser.id}
                        onClick={() => {
                          setError('');
                          setSuccessMessage('');
                          setDeleteTarget(u);
                        }}
                        title={u.id === currentUser.id ? 'You cannot delete your own account' : `Delete ${u.name || u.username}`}
                        aria-label={`Delete ${u.name || u.username}`}
                        className="inline-flex items-center justify-center w-8 h-8 rounded-lg text-red-600 hover:bg-red-50 disabled:text-slate-300 disabled:hover:bg-transparent disabled:cursor-not-allowed"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {pagination.total > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {pagination.from ?? 0}–{pagination.to ?? 0} of {pagination.total}</span>
            <div className="flex items-center gap-2">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {pagination.currentPage} of {pagination.lastPage}</span>
              <button onClick={() => setPage((p) => Math.min(pagination.lastPage, p + 1))} disabled={page === pagination.lastPage} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {viewTarget && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 p-5 overflow-y-auto"
          onClick={() => setViewTarget(null)}
        >
          <div
            className="w-full max-w-lg my-auto bg-white rounded-2xl shadow-2xl overflow-hidden"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="relative bg-gradient-to-br from-accent to-accent-dark px-5 pt-5 pb-6 text-white">
              <button
                type="button"
                onClick={() => setViewTarget(null)}
                className="absolute top-3 right-3 p-1.5 rounded-lg text-white/80 hover:bg-white/15 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
              <div className="flex items-center gap-3">
                <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-sm ${avatarColor(viewTarget.id)}`}>
                  {initials(viewTarget.name, viewTarget.username)}
                </div>
                <div className="min-w-0">
                  <h2 className="font-bold text-base leading-tight truncate">{viewTarget.name || viewTarget.username}</h2>
                  <p className="text-xs text-white/75">@{viewTarget.username}</p>
                </div>
                <span className="ml-auto shrink-0 text-[10px] font-bold uppercase px-2.5 py-1 rounded-full bg-white/15 border border-white/25">
                  {roleLabel(viewTarget.role)}
                </span>
              </div>
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
                <ViewField
                  label="Password"
                  value={viewTarget.login_password}
                  mono
                />
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
                  const user = viewTarget;
                  setViewTarget(null);
                  selectUser(user);
                }}
                className="inline-flex items-center gap-1.5 bg-accent hover:bg-accent-dark text-white text-xs font-bold px-4 py-2 rounded-lg"
              >
                <Pencil className="w-3.5 h-3.5" />
                Edit
              </button>
              <button
                type="button"
                onClick={() => setViewTarget(null)}
                className="text-xs font-bold px-4 py-2 rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {selected && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 p-5 overflow-y-auto"
          onClick={() => setSelected(null)}
        >
          <div
            className="w-full max-w-3xl my-auto bg-white rounded-2xl shadow-2xl overflow-hidden"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="relative bg-gradient-to-br from-accent to-accent-dark px-5 pt-5 pb-6 text-white">
              <button
                type="button"
                onClick={() => setSelected(null)}
                className="absolute top-3 right-3 p-1.5 rounded-lg text-white/80 hover:bg-white/15 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
              <div className="flex items-center gap-3">
                <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-sm ${avatarColor(selected.id)}`}>
                  {initials(selected.name, selected.username)}
                </div>
                <div className="min-w-0">
                  <h2 className="font-bold text-base leading-tight truncate">{selected.name || selected.username}</h2>
                  <p className="text-xs text-white/75">@{selected.username} {selected.email && `· ${selected.email}`}</p>
                </div>
                {isSelf && (
                  <span className="ml-auto shrink-0 flex items-center gap-1 text-[11px] font-semibold bg-white/15 border border-white/25 rounded-lg px-2.5 py-1">
                    <Lock className="w-3 h-3" />
                    Your account
                  </span>
                )}
              </div>
            </div>

            <div className="p-5 space-y-5 max-h-[70vh] overflow-y-auto">
              {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

              <EditSection title="Identity" icon={<Users2 className="w-3.5 h-3.5" />}>
                <TextField label="Full Name" value={editName} onChange={setEditName} span={2} />
                <TextField label="Phone No." value={editMobile} onChange={setEditMobile} icon={<Phone className="w-3.5 h-3.5" />} />
                <TextField label="Email" value={editEmail} onChange={setEditEmail} icon={<Mail className="w-3.5 h-3.5" />} />
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Password</label>
                  <div className="relative">
                    <input
                      type={showEditPassword ? 'text' : 'password'}
                      value={editPassword}
                      onChange={(e) => setEditPassword(e.target.value)}
                      placeholder={selected.login_password ? 'Leave blank to keep current' : 'Set a password to show it here'}
                      autoComplete="new-password"
                      className="w-full text-xs border border-slate-300 rounded-lg py-1.5 pl-2.5 pr-8 focus:outline-none focus:ring-2 focus:ring-accent"
                    />
                    <button
                      type="button"
                      onClick={() => setShowEditPassword((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                      title={showEditPassword ? 'Hide password' : 'Show password'}
                    >
                      {showEditPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  {selected.login_password && !editPassword && (
                    <p className="mt-1 font-mono text-[11px] text-slate-500">Current: {selected.login_password}</p>
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
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Role</label>
                  <select
                    value={editRole}
                    onChange={(e) => setEditRole(e.target.value)}
                    disabled={isSelf}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-slate-400 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    {(editRole && !roles.includes(editRole) ? [...roles, editRole] : roles).map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Department</label>
                  <select
                    value={editDepartment}
                    onChange={(e) => setEditDepartment(e.target.value)}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Status</label>
                  <label className={`flex items-center gap-2 text-xs font-semibold px-2.5 py-[7px] border rounded-lg ${isSelf ? 'text-slate-400 bg-slate-50' : 'text-slate-700'}`}>
                    <input
                      type="checkbox"
                      checked={editActive}
                      disabled={isSelf}
                      onChange={(e) => setEditActive(e.target.checked)}
                      className="accent-accent"
                    />
                    Active
                  </label>
                </div>
              </EditSection>

              <EditSection title="Jurisdiction" icon={<MapPin className="w-3.5 h-3.5" />}>
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">District</label>
                  <select
                    value={editDistrict}
                    onChange={(e) => {
                      setEditDistrict(e.target.value);
                      setEditBlock('');
                      setEditPanchayat('');
                    }}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Block</label>
                  <select
                    value={editBlock}
                    onChange={(e) => {
                      setEditBlock(e.target.value);
                      setEditPanchayat('');
                    }}
                    disabled={!editDistrict}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-slate-400 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {blocksForDistrict.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Panchayat</label>
                  <select
                    value={editPanchayat}
                    onChange={(e) => setEditPanchayat(e.target.value)}
                    disabled={!editBlock}
                    className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-slate-400 focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    <option value="">— none —</option>
                    {panchayatsForBlock.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </div>
              </EditSection>
            </div>

            <div className="flex items-center gap-2 px-5 py-4 border-t border-slate-100 bg-slate-50">
              <button
                disabled={isSubmitting}
                onClick={save}
                className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg"
              >
                {isSubmitting ? 'Saving…' : 'Save Changes'}
              </button>
              <button
                type="button"
                onClick={() => setSelected(null)}
                className="text-xs font-bold px-4 py-2 rounded-lg border border-slate-200 text-slate-600 hover:bg-white"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {deleteTarget && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/40 p-5"
          onClick={() => { if (!isDeleting) setDeleteTarget(null); }}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="delete-user-title"
            className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-full bg-red-50 text-red-600">
              <Trash2 className="h-5 w-5" />
            </div>
            <h2 id="delete-user-title" className="text-lg font-bold text-slate-900">Delete user?</h2>
            <p className="mt-2 text-sm leading-6 text-slate-500">
              <b className="text-slate-800">{deleteTarget.name || deleteTarget.username}</b> का account permanently delete हो जाएगा। यह action undo नहीं हो सकता।
            </p>
            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                disabled={isDeleting}
                onClick={() => setDeleteTarget(null)}
                className="rounded-lg border border-slate-200 px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={isDeleting}
                onClick={removeUser}
                className="inline-flex items-center gap-1.5 rounded-lg bg-red-600 px-4 py-2 text-xs font-bold text-white hover:bg-red-700 disabled:opacity-50"
              >
                <Trash2 className="h-3.5 w-3.5" />
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
      <p className="flex items-center gap-1.5 text-[10px] font-bold text-slate-400 uppercase tracking-wide mb-2">
        {icon} {title}
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs bg-slate-50 border border-slate-100 rounded-xl p-3">
        {children}
      </div>
    </div>
  );
}

function ViewField({ label, value, badge, mono }: { label: string; value?: string | null; badge?: 'emerald' | 'slate'; mono?: boolean }) {
  return (
    <div>
      <p className="text-[10px] font-bold text-slate-400 uppercase mb-0.5">{label}</p>
      {badge ? (
        <span className={`inline-block text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
          badge === 'emerald' ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-slate-100 text-slate-500 border-slate-200'
        }`}>
          {value || '—'}
        </span>
      ) : (
        <p className={`text-slate-700 font-medium ${mono ? 'font-mono text-[11px]' : ''}`}>{value || '—'}</p>
      )}
    </div>
  );
}

function PasswordReveal({
  password, hidden, onToggle, onSet,
}: {
  password?: string | null;
  hidden: boolean;
  onToggle: () => void;
  onSet: () => void;
}) {
  if (!password) {
    return (
      <button
        type="button"
        onClick={onSet}
        className="text-[11px] font-semibold text-accent hover:underline"
        title="Password was set before it could be stored for admin view. Set a new one to show it here."
      >
        Set password
      </button>
    );
  }

  return (
    <div className="flex items-center gap-1.5 min-w-[120px]">
      <span className="font-mono text-[11px] text-slate-800">{hidden ? '••••••••' : password}</span>
      <button
        type="button"
        onClick={onToggle}
        className="p-1 rounded-md text-slate-400 hover:bg-slate-100 hover:text-slate-600"
        title={hidden ? 'Show password' : 'Hide password'}
      >
        {hidden ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
      </button>
    </div>
  );
}

function EditSection({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <p className="flex items-center gap-1.5 text-[10px] font-bold text-slate-400 uppercase tracking-wide mb-2">
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
      <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">{label}</label>
      <div className="relative">
        {icon && <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400">{icon}</span>}
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className={`w-full text-xs border border-slate-300 rounded-lg py-1.5 focus:outline-none focus:ring-2 focus:ring-accent ${icon ? 'pl-8 pr-2.5' : 'px-2.5'}`}
        />
      </div>
    </div>
  );
}
