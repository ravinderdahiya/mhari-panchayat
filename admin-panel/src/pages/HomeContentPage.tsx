import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { ExternalLink } from 'lucide-react';
import * as api from '../services/api';
import type { SiteSettings } from '../services/api';

const inputClass =
  'w-full text-sm border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-sidebar focus:ring-1 focus:ring-sidebar';

// [key, label, hint?]
const CONTACT: [string, string, string?][] = [
  ['helpline', 'Helpline number', 'Shown in the home page footer, e.g. 1800-xxx-xxxx'],
  ['support_email', 'Support e-mail'],
  ['office_hours', 'Office hours', 'e.g. Mon-Sat, 9:00 AM - 5:30 PM'],
];

const ANNOUNCEMENT: [string, string, boolean?][] = [
  ['announcement_tag', 'Tag (small label above the title, e.g. NEW)'],
  ['announcement_title', 'Title'],
  ['announcement_body', 'Details', true],
  ['announcement_cta_label', 'Button text'],
];

export default function HomeContentPage() {
  const [values, setValues] = useState<SiteSettings>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  useEffect(() => {
    api.getSiteSettings()
      .then((res) => setValues(res.data))
      .catch((reason: Error) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const set = (key: string, value: string) => { setValues((v) => ({ ...v, [key]: value })); setSaved(''); };
  const active = values.announcement_active === '1';

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError('');
    try {
      const res = await api.updateSiteSettings(values);
      setValues(res.data);
      setSaved('Saved. The public home page shows this within 5 minutes.');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not save');
    } finally {
      setSaving(false);
    }
  };

  const field = (key: string, label: string, hint?: string, multiline?: boolean) => (
    <label key={key} className="block text-xs font-semibold text-slate-600 space-y-1">
      {label}
      {multiline ? (
        <textarea className={`${inputClass} min-h-20`} maxLength={600} value={values[key] ?? ''} onChange={(e) => set(key, e.target.value)} />
      ) : (
        <input className={inputClass} maxLength={200} value={values[key] ?? ''} onChange={(e) => set(key, e.target.value)} />
      )}
      {hint && <span className="block font-normal text-slate-400">{hint}</span>}
    </label>
  );

  return (
    <form onSubmit={submit} className="max-w-3xl space-y-5">
      {error && <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">{error}</div>}
      {saved && <div role="status" className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-lg px-3 py-2">{saved}</div>}

      <p className="text-xs text-slate-500">
        The numbers, asset map, app links and complaint tracker on the public home page update by themselves.
        This page controls the parts that are written by hand.{' '}
        <a href={import.meta.env.BASE_URL} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 font-semibold text-sidebar hover:underline">
          Open home page <ExternalLink size={12} />
        </a>
      </p>

      {loading ? <p className="text-sm text-slate-500">Loading…</p> : (
        <>
          <section className="bg-white border border-slate-200 rounded-xl p-5 space-y-4">
            <h2 className="text-sm font-bold text-slate-700">Contact (footer)</h2>
            <div className="grid sm:grid-cols-2 gap-4">
              {CONTACT.map(([key, label, hint]) => field(key, label, hint))}
            </div>
          </section>

          <section className="bg-white border border-slate-200 rounded-xl p-5 space-y-4">
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-sm font-bold text-slate-700">Announcement banner</h2>
              <label className="inline-flex items-center gap-2 text-xs font-semibold text-slate-600 cursor-pointer">
                <input type="checkbox" checked={active} onChange={(e) => set('announcement_active', e.target.checked ? '1' : '0')} />
                Show on home page
              </label>
            </div>

            <div className="grid lg:grid-cols-2 gap-5">
              <div className="space-y-3">
                <p className="text-[11px] font-bold tracking-wide text-slate-400">ENGLISH</p>
                {ANNOUNCEMENT.map(([key, label, multi]) => field(key, label, undefined, multi))}
              </div>
              <div className="space-y-3">
                <p className="text-[11px] font-bold tracking-wide text-slate-400">हिंदी (optional)</p>
                {ANNOUNCEMENT.map(([key, label, multi]) => field(`${key}_hi`, label, undefined, multi))}
              </div>
            </div>
            {field('announcement_cta_url', 'Button link', 'A full https:// address, or a path on this site such as /mhari-panchayat/terms-of-service.html')}
            <p className="text-xs text-slate-400">The banner needs a title to appear. If the Hindi fields are empty, visitors on the Hindi page see the English text.</p>
          </section>

          <button type="submit" disabled={saving} className="text-sm font-semibold text-white bg-sidebar rounded-lg px-5 py-2 disabled:opacity-50 cursor-pointer">
            {saving ? 'Saving…' : 'Save'}
          </button>
        </>
      )}
    </form>
  );
}
