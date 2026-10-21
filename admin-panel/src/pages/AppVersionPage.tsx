import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { Smartphone } from 'lucide-react';
import * as api from '../services/api';
import type { AppVersionSetting } from '../services/api';

type Platform = 'android' | 'ios';

const PLATFORMS: { id: Platform; label: string; storeHint: string }[] = [
  { id: 'android', label: 'Android (Play Store)', storeHint: 'https://play.google.com/store/apps/details?id=in.hsac.mharipanchayat' },
  { id: 'ios', label: 'iOS (App Store)', storeHint: 'https://apps.apple.com/app/id<your-app-id>' },
];

const inputClass =
  'w-full text-sm border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-sidebar focus:ring-1 focus:ring-sidebar';

export default function AppVersionPage() {
  const [rows, setRows] = useState<AppVersionSetting[]>([]);
  const [platform, setPlatform] = useState<Platform>('android');
  const [setting, setSetting] = useState<AppVersionSetting | null>(null);
  const [latest, setLatest] = useState('');
  const [min, setMin] = useState('');
  const [storeUrl, setStoreUrl] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState('');

  const apply = (s: AppVersionSetting) => {
    setSetting(s);
    setLatest(String(s.latest_version_code));
    setMin(String(s.min_version_code));
    setStoreUrl(s.store_url);
    setMessage(s.message ?? '');
  };

  // A platform with no saved row yet (e.g. iOS before its first release) starts
  // from permissive defaults, so nothing is forced until an admin saves it.
  const showPlatform = (next: Platform, source: AppVersionSetting[]) => {
    setPlatform(next);
    setError('');
    setSaved('');
    const row = source.find((v) => v.platform === next);
    if (row) {
      apply(row);
    } else {
      setSetting(null);
      setLatest('1');
      setMin('1');
      setStoreUrl('');
      setMessage('');
    }
  };

  useEffect(() => {
    api.getAppVersions()
      .then((res) => {
        setRows(res.data);
        showPlatform('android', res.data);
      })
      .catch((reason: Error) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const latestNum = Number(latest);
  const minNum = Number(min);
  const valid = Number.isInteger(latestNum) && Number.isInteger(minNum)
    && latestNum >= 1 && minNum >= 1 && minNum <= latestNum && storeUrl.trim() !== '';

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || saving) return;
    setSaving(true);
    setError('');
    setSaved('');
    try {
      const res = await api.updateAppVersion(platform, {
        latest_version_code: latestNum,
        min_version_code: minNum,
        store_url: storeUrl.trim(),
        message: message.trim() === '' ? null : message.trim(),
      });
      apply(res.data);
      setRows((current) => [...current.filter((v) => v.platform !== platform), res.data]);
      setSaved('Saved. The app picks this up the next time it is opened.');
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not save');
    } finally {
      setSaving(false);
    }
  };

  const forcing = valid && minNum === latestNum;

  return (
    <div className="max-w-2xl space-y-4">
      {error && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
          {error}
        </div>
      )}
      {saved && (
        <div role="status" className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-lg px-3 py-2">
          {saved}
        </div>
      )}

      <form onSubmit={submit} className="bg-white border border-slate-200 rounded-xl p-5 space-y-4">
        <div className="flex items-center gap-2 text-slate-700">
          <Smartphone size={18} />
          <h2 className="text-sm font-bold">App release settings</h2>
        </div>

        <div className="flex gap-2" role="tablist">
          {PLATFORMS.map((p) => (
            <button
              key={p.id}
              type="button"
              role="tab"
              aria-selected={platform === p.id}
              onClick={() => showPlatform(p.id, rows)}
              className={`text-xs font-semibold rounded-full border px-3 py-1.5 cursor-pointer ${
                platform === p.id ? 'bg-sidebar text-white border-sidebar' : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>

        {loading ? (
          <p className="text-sm text-slate-500">Loading…</p>
        ) : (
          <>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <label className="block text-xs font-semibold text-slate-600 space-y-1">
                Latest version code
                <input className={inputClass} inputMode="numeric" value={latest} onChange={(e) => setLatest(e.target.value)} />
                <span className="block font-normal text-slate-400">
                  The build number (the +N in pubspec) of the newest release. Older builds see an optional "Update" prompt.
                </span>
              </label>
              <label className="block text-xs font-semibold text-slate-600 space-y-1">
                Minimum version code
                <input className={inputClass} inputMode="numeric" value={min} onChange={(e) => setMin(e.target.value)} />
                <span className="block font-normal text-slate-400">
                  Builds below this are forced to update and cannot sign in.
                </span>
              </label>
            </div>

            <label className="block text-xs font-semibold text-slate-600 space-y-1">
              {platform === 'ios' ? 'App Store URL' : 'Play Store URL'}
              <input className={inputClass} placeholder={PLATFORMS.find((p) => p.id === platform)?.storeHint} value={storeUrl} onChange={(e) => setStoreUrl(e.target.value)} />
            </label>

            <label className="block text-xs font-semibold text-slate-600 space-y-1">
              Message shown to users (optional)
              <input className={inputClass} maxLength={255} value={message} onChange={(e) => setMessage(e.target.value)} />
            </label>

            {min !== '' && latest !== '' && minNum > latestNum && (
              <p className="text-xs text-red-600">The minimum version cannot be higher than the latest version.</p>
            )}
            {forcing && (
              <p className="text-xs text-amber-700 bg-amber-50 border border-amber-100 rounded-lg px-3 py-2">
                Minimum equals latest: every older build will be forced to update.
              </p>
            )}

            <div className="flex items-center gap-3">
              <button
                type="submit"
                disabled={!valid || saving}
                className="text-sm font-semibold text-white bg-sidebar rounded-lg px-4 py-2 disabled:opacity-50 cursor-pointer disabled:cursor-not-allowed"
              >
                {saving ? 'Saving…' : 'Save'}
              </button>
              {setting?.updated_at && (
                <span className="text-xs text-slate-400">
                  Last updated {new Date(setting.updated_at).toLocaleString('en-IN')}
                </span>
              )}
            </div>
          </>
        )}
      </form>
    </div>
  );
}
