import { useEffect, useMemo, useState } from 'react';
import { Search, Users as UsersIcon, Inbox, ChevronLeft, ChevronRight, Lock, Trash2 } from 'lucide-react';
import * as api from '../services/api';
import { masterApi } from '../services/api';
import { ALL_ROLES } from '../types';
import type { AdminUser, Department, User } from '../types';

interface UsersPageProps {
  currentUser: User;
}

const PAGE_SIZE = 10;

function roleLabel(role: string) {
  return role.replace(/_/g, ' ');
}

export default function UsersPage({ currentUser }: UsersPageProps) {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState<'All' | 'Active' | 'Inactive'>('All');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<AdminUser | null>(null);
  const [error, setError] = useState('');
  const [successMessage, setSuccessMessage] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const [editRole, setEditRole] = useState('');
  const [editDepartment, setEditDepartment] = useState('');
  const [editActive, setEditActive] = useState(true);

  const load = async () => {
    setIsLoading(true);
    try {
      const { users } = await api.getUsers();
      setUsers(users);
      if (selected) {
        const fresh = users.find((u) => u.id === selected.id) || null;
        setSelected(fresh);
        if (fresh) {
          setEditRole(fresh.role);
          setEditDepartment(fresh.department_id ? String(fresh.department_id) : '');
          setEditActive(fresh.is_active);
        }
      }
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
    masterApi('departments').list().then(({ items }) => setDepartments(items)).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => { setPage(1); }, [searchQuery, roleFilter, statusFilter]);

  const filtered = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return users
      .filter((u) => roleFilter === 'All' || u.role === roleFilter)
      .filter((u) => statusFilter === 'All' || (statusFilter === 'Active') === u.is_active)
      .filter((u) => !q || [u.username, u.name, u.email].filter(Boolean).join(' ').toLowerCase().includes(q));
  }, [users, searchQuery, roleFilter, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  const selectUser = (u: AdminUser) => {
    setSelected(u);
    setEditRole(u.role);
    setEditDepartment(u.department_id ? String(u.department_id) : '');
    setEditActive(u.is_active);
    setError('');
  };

  const isSelf = selected?.id === currentUser.id;

  const save = async () => {
    if (!selected) return;
    setIsSubmitting(true);
    setError('');
    try {
      const { user } = await api.updateUser(selected.id, {
        role: editRole,
        department_id: editDepartment ? Number(editDepartment) : null,
        is_active: editActive,
      });
      setUsers((prev) => prev.map((u) => (u.id === user.id ? user : u)));
      setSelected(user);
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
      setUsers((prev) => prev.filter((user) => user.id !== deleteTarget.id));
      if (selected?.id === deleteTarget.id) setSelected(null);
      setSuccessMessage(message || 'User deleted successfully');
      setDeleteTarget(null);
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
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search users…"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select value={roleFilter} onChange={(e) => setRoleFilter(e.target.value)} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Roles</option>
          {ALL_ROLES.map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}
        </select>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value as any)} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Statuses</option>
          <option value="Active">Active</option>
          <option value="Inactive">Inactive</option>
        </select>
        <span className="text-xs text-slate-400 ml-auto flex items-center gap-1.5">
          <UsersIcon className="w-3.5 h-3.5" />
          {filtered.length} users
        </span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        {isLoading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : filtered.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No users match your filters.</p>
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-2.5">Username</th>
                <th className="text-left p-2.5">Name</th>
                <th className="text-left p-2.5">Email</th>
                <th className="text-left p-2.5">Role</th>
                <th className="text-left p-2.5">Department</th>
                <th className="text-left p-2.5">Status</th>
                <th className="text-left p-2.5">Joined</th>
                <th className="text-right p-2.5">Action</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((u) => (
                <tr
                  key={u.id}
                  onClick={() => selectUser(u)}
                  className={`border-t border-slate-100 cursor-pointer hover:bg-slate-50 ${selected?.id === u.id ? 'bg-accent/10' : ''}`}
                >
                  <td className="p-2.5 font-semibold text-slate-800">
                    {u.username}
                    {u.id === currentUser.id && <span className="ml-1.5 text-[9px] text-slate-400">(you)</span>}
                  </td>
                  <td className="p-2.5 text-slate-600">{u.name || '—'}</td>
                  <td className="p-2.5 text-slate-500">{u.email || '—'}</td>
                  <td className="p-2.5">
                    <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                      {roleLabel(u.role)}
                    </span>
                  </td>
                  <td className="p-2.5 text-slate-500">{u.department?.name || '—'}</td>
                  <td className="p-2.5">
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${
                      u.is_active ? 'bg-status-closed/10 text-status-closed border-status-closed/25' : 'bg-slate-100 text-slate-500 border-slate-200'
                    }`}>
                      {u.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="p-2.5 text-slate-400">{new Date(u.created_at).toLocaleDateString()}</td>
                  <td className="p-2.5 text-right" onClick={(event) => event.stopPropagation()}>
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
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {selected && (
        <div className="bg-white border border-slate-200 rounded-2xl p-5 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="font-bold text-slate-900">{selected.name || selected.username}</h2>
              <p className="text-xs text-slate-400">@{selected.username} {selected.email && `· ${selected.email}`}</p>
            </div>
            {isSelf && (
              <span className="flex items-center gap-1 text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-2.5 py-1">
                <Lock className="w-3 h-3" />
                This is your own account
              </span>
            )}
          </div>

          {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Role</label>
              <select
                value={editRole}
                onChange={(e) => setEditRole(e.target.value)}
                disabled={isSelf}
                className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 disabled:bg-slate-50 disabled:text-slate-400 focus:outline-none focus:ring-2 focus:ring-accent"
              >
                {ALL_ROLES.map((r) => <option key={r} value={r}>{roleLabel(r)}</option>)}
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
              <label className={`flex items-center gap-2 text-xs font-semibold px-2.5 py-1.5 border rounded-lg ${isSelf ? 'text-slate-400 bg-slate-50' : 'text-slate-700'}`}>
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
          </div>

          <button
            disabled={isSubmitting}
            onClick={save}
            className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg"
          >
            {isSubmitting ? 'Saving…' : 'Save Changes'}
          </button>
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
