import { useState } from 'react';
import type { FormEvent } from 'react';
import { ChevronRight, Database, Globe, Smartphone } from 'lucide-react';
import * as api from '../services/api';
import type { View } from '../components/Layout';

const inputClass =
  'w-full text-sm border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-sidebar focus:ring-1 focus:ring-sidebar';

const SHORTCUTS: { view: View; child?: string; icon: typeof Globe; title: string; hint: string }[] = [
  { view: 'master', child: 'complaint-priorities', icon: Database, title: 'Complaint priorities & SLA', hint: 'Set the hours allowed per priority before a complaint escalates' },
  { view: 'app-version', icon: Smartphone, title: 'App version', hint: 'Minimum and latest mobile app version, store links' },
  { view: 'home-content', icon: Globe, title: 'Home page', hint: 'Helpline, office hours and the announcement banner' },
];

interface Props {
  onNavigate: (view: View, childId?: string) => void;
}

export default function SettingsPage({ onNavigate }: Props) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState('');

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setError('');
    setDone('');
    if (next !== confirm) {
      setError('New password and confirmation do not match.');
      return;
    }
    setSaving(true);
    try {
      const res = await api.changePassword(current, next, confirm);
      setDone(res.message || 'Password changed.');
      setCurrent('');
      setNext('');
      setConfirm('');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not change the password');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="max-w-3xl space-y-5">
      <section className="bg-white border border-slate-200 rounded-xl p-5">
        <h2 className="text-sm font-bold text-slate-700">Change password</h2>
        <p className="mt-1 text-xs text-slate-400">Use at least 8 characters. You stay signed in on this device.</p>
        <form onSubmit={submit} className="mt-4 space-y-3 max-w-md">
          {error && <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">{error}</div>}
          {done && <div role="status" className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-lg px-3 py-2">{done}</div>}
          <label className="block text-xs font-semibold text-slate-600 space-y-1">
            Current password
            <input type="password" autoComplete="current-password" required className={inputClass} value={current} onChange={(e) => setCurrent(e.target.value)} />
          </label>
          <label className="block text-xs font-semibold text-slate-600 space-y-1">
            New password
            <input type="password" autoComplete="new-password" required minLength={8} className={inputClass} value={next} onChange={(e) => setNext(e.target.value)} />
          </label>
          <label className="block text-xs font-semibold text-slate-600 space-y-1">
            Confirm new password
            <input type="password" autoComplete="new-password" required minLength={8} className={inputClass} value={confirm} onChange={(e) => setConfirm(e.target.value)} />
          </label>
          <button type="submit" disabled={saving} className="text-sm font-semibold text-white bg-sidebar rounded-lg px-5 py-2 disabled:opacity-50 cursor-pointer">
            {saving ? 'Saving…' : 'Change password'}
          </button>
        </form>
      </section>

      <section className="bg-white border border-slate-200 rounded-xl divide-y divide-slate-100">
        <h2 className="px-5 py-3 text-sm font-bold text-slate-700">System configuration</h2>
        {SHORTCUTS.map(({ view, child, icon: Icon, title, hint }) => (
          <button key={view} type="button" onClick={() => onNavigate(view, child)}
            className="w-full flex items-center gap-3 px-5 py-3 text-left hover:bg-slate-50 cursor-pointer">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent-dark"><Icon size={17} /></span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold text-slate-700">{title}</span>
              <span className="block text-xs text-slate-400">{hint}</span>
            </span>
            <ChevronRight size={16} className="text-slate-300" />
          </button>
        ))}
      </section>
    </div>
  );
}
