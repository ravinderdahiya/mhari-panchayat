import { useEffect, useMemo, useState } from 'react';
import { ShieldCheck, Check } from 'lucide-react';
import * as api from '../services/api';
import type { RolePermissionMatrix } from '../types';

function roleLabel(role: string) {
  return role.replace(/_/g, ' ');
}

export default function RolesPage() {
  const [data, setData] = useState<RolePermissionMatrix | null>(null);
  const [draft, setDraft] = useState<Record<string, Set<string>>>({});
  const [error, setError] = useState('');
  const [savingRole, setSavingRole] = useState<string | null>(null);
  const [savedRole, setSavedRole] = useState<string | null>(null);

  useEffect(() => {
    api.getRolePermissions()
      .then((res) => {
        setData(res);
        const next: Record<string, Set<string>> = {};
        res.roles.forEach((r) => { next[r] = new Set(res.matrix[r] || []); });
        setDraft(next);
      })
      .catch((err) => setError((err as Error).message));
  }, []);

  const groups = useMemo(() => {
    if (!data) return [];
    const byGroup: Record<string, typeof data.permissions> = {};
    data.permissions.forEach((p) => {
      (byGroup[p.group] ||= []).push(p);
    });
    return Object.entries(byGroup);
  }, [data]);

  const isDirty = (role: string) => {
    if (!data) return false;
    const original = new Set(data.matrix[role] || []);
    const current = draft[role] || new Set();
    if (original.size !== current.size) return true;
    for (const key of current) if (!original.has(key)) return true;
    return false;
  };

  const toggle = (role: string, key: string) => {
    setSavedRole(null);
    setDraft((prev) => {
      const next = new Set(prev[role]);
      if (next.has(key)) next.delete(key); else next.add(key);
      return { ...prev, [role]: next };
    });
  };

  const save = async (role: string) => {
    if (!data) return;
    setSavingRole(role);
    setError('');
    try {
      const keys = Array.from(draft[role] || []);
      await api.updateRolePermissions(role, keys);
      setData((prev) => (prev ? { ...prev, matrix: { ...prev.matrix, [role]: keys } } : prev));
      setSavedRole(role);
      setTimeout(() => setSavedRole((r) => (r === role ? null : r)), 2000);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSavingRole(null);
    }
  };

  if (!data) {
    return error
      ? <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>
      : <p className="text-sm text-slate-400">Loading…</p>;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <ShieldCheck className="w-4 h-4 text-accent-dark" />
        <h2 className="text-sm font-bold text-slate-800">Roles &amp; Permissions</h2>
      </div>

      {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        <table className="text-xs border-collapse">
          <thead>
            <tr>
              <th className="sticky left-0 bg-slate-50 z-10 p-2.5 text-left align-bottom" rowSpan={2}>Role</th>
              {groups.map(([group, perms]) => (
                <th key={group} colSpan={perms.length} className="p-2 text-center text-[10px] font-bold text-slate-500 uppercase bg-slate-50 border-b border-slate-200">
                  {group}
                </th>
              ))}
              <th className="bg-slate-50 p-2.5" rowSpan={2}></th>
            </tr>
            <tr>
              {groups.flatMap(([, perms]) => perms.map((p) => (
                <th key={p.key} className="p-2 text-center text-[10px] font-semibold text-slate-500 bg-slate-50 border-b border-slate-200 whitespace-nowrap" style={{ writingMode: 'horizontal-tb' }}>
                  {p.label}
                </th>
              )))}
            </tr>
          </thead>
          <tbody>
            {data.roles.map((role) => {
              const dirty = isDirty(role);
              return (
                <tr key={role} className="border-t border-slate-100 hover:bg-slate-50/60">
                  <td className="sticky left-0 bg-white z-10 p-2.5 font-bold text-slate-800 uppercase whitespace-nowrap">
                    {roleLabel(role)}
                  </td>
                  {groups.flatMap(([, perms]) => perms.map((p) => (
                    <td key={p.key} className="p-2 text-center">
                      <input
                        type="checkbox"
                        checked={draft[role]?.has(p.key) ?? false}
                        onChange={() => toggle(role, p.key)}
                        className="w-3.5 h-3.5 accent-accent cursor-pointer"
                      />
                    </td>
                  )))}
                  <td className="p-2 whitespace-nowrap">
                    {dirty ? (
                      <button
                        disabled={savingRole === role}
                        onClick={() => save(role)}
                        className="text-[11px] font-bold bg-accent hover:bg-accent-dark disabled:opacity-50 text-white px-2.5 py-1 rounded-lg"
                      >
                        {savingRole === role ? 'Saving…' : 'Save'}
                      </button>
                    ) : savedRole === role ? (
                      <span className="flex items-center gap-1 text-[11px] font-bold text-status-closed">
                        <Check className="w-3.5 h-3.5" />
                        Saved
                      </span>
                    ) : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
