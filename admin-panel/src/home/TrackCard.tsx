import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { ArrowRight, CheckCircle2, Clock3, Loader2, TriangleAlert } from 'lucide-react';
import * as api from '../services/api';
import type { TrackedComplaint } from '../services/api';
import type { Lang } from './strings';

type T = (key: string, vars?: Record<string, string | number>) => string;

interface Props {
  t: T;
  lang: Lang;
  /** Complaint ID from a shared link (?track=...) */
  initialId?: string;
}

const STEP_KEYS = ['submitted', 'routed', 'assigned', 'under_review', 'resolved', 'closed'];

function formatDate(value: string | null, lang: Lang) {
  if (!value) return '';
  return new Intl.DateTimeFormat(lang === 'hi' ? 'hi-IN' : 'en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
  }).format(new Date(value));
}

export default function TrackCard({ t, lang, initialId }: Props) {
  const [complaintId, setComplaintId] = useState(initialId ?? '');
  const [mobile, setMobile] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<TrackedComplaint | null>(null);

  useEffect(() => {
    if (initialId) setComplaintId(initialId);
  }, [initialId]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    const id = complaintId.trim();
    if (!id) return setError(t('errId'));
    if (!/^[6-9]\d{9}$/.test(mobile)) return setError(t('errMobile'));

    setBusy(true);
    setError('');
    try {
      const res = await api.trackComplaint(id, mobile);
      setResult(res.data);
    } catch (reason) {
      setResult(null);
      setError(reason instanceof Error ? reason.message : t('loadErr'));
    } finally {
      setBusy(false);
    }
  };

  const sla = result && !result.rejected && result.status !== 'Resolved' && result.status !== 'Closed' && result.days_left !== null
    ? result.days_left > 0
      ? { text: t('slaLeft', { n: result.days_left }), tone: 'text-amber-700 bg-amber-50 border-amber-200' }
      : result.days_left === 0
        ? { text: t('slaToday'), tone: 'text-amber-700 bg-amber-50 border-amber-200' }
        : { text: t('slaBreach', { n: Math.abs(result.days_left) }), tone: 'text-red-700 bg-red-50 border-red-200' }
    : result && (result.status === 'Resolved' || result.status === 'Closed')
      ? { text: t('slaDone'), tone: 'text-emerald-700 bg-emerald-50 border-emerald-200' }
      : null;

  return (
    <div id="track" className="scroll-mt-24 rounded-2xl border border-line bg-white p-5 sm:p-6 shadow-[0_20px_50px_-28px_rgba(22,51,44,0.45)]">
      <div className="flex items-start justify-between gap-3">
        <h2 className="font-serif text-xl font-semibold text-sidebar leading-snug">{t('trackTitle')}</h2>
        <span className="shrink-0 text-[10px] font-semibold tracking-wide text-accent-dark bg-accent-soft/60 rounded-full px-2.5 py-1">
          {t('trackTag')}
        </span>
      </div>

      {!result ? (
        <form onSubmit={submit} className="mt-4 space-y-3" noValidate>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label className="block text-[11px] font-semibold text-muted">
              {t('trackId')}
              <input
                value={complaintId}
                onChange={(e) => setComplaintId(e.target.value.toUpperCase())}
                placeholder="COMP-HSR-10_2026-001"
                autoComplete="off"
                className="mt-1 w-full rounded-lg border border-line bg-cream/50 px-3 py-2.5 text-sm font-mono text-ink outline-none focus:border-sidebar focus:ring-1 focus:ring-sidebar"
              />
            </label>
            <label className="block text-[11px] font-semibold text-muted">
              {t('trackMobile')}
              <input
                value={mobile}
                onChange={(e) => setMobile(e.target.value.replace(/\D/g, '').slice(0, 10))}
                inputMode="numeric"
                placeholder="98XXXXXXXX"
                autoComplete="tel-national"
                className="mt-1 w-full rounded-lg border border-line bg-cream/50 px-3 py-2.5 text-sm font-mono text-ink outline-none focus:border-sidebar focus:ring-1 focus:ring-sidebar"
              />
            </label>
          </div>
          {error && (
            <p role="alert" className="flex items-start gap-2 text-xs text-red-700 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
              <TriangleAlert size={14} className="mt-0.5 shrink-0" /> {error}
            </p>
          )}
          <button
            type="submit"
            disabled={busy}
            className="w-full inline-flex items-center justify-center gap-2 rounded-lg bg-sidebar px-4 py-3 text-sm font-semibold text-white hover:bg-sidebar-hover disabled:opacity-60 cursor-pointer"
          >
            {busy ? <><Loader2 size={16} className="animate-spin" /> {t('trackBusy')}</> : t('trackBtn')}
          </button>
          <p className="text-[11px] text-muted">{t('trackHint')}</p>
          <p className="text-[11px] text-muted font-mono">{t('trackExample')}</p>
        </form>
      ) : (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="font-mono text-sm font-semibold text-sidebar break-all">{result.complaint_id}</p>
            <span className={`text-xs font-semibold rounded-full px-3 py-1 border ${result.rejected ? 'text-red-700 bg-red-50 border-red-200' : 'text-sidebar bg-accent-soft/50 border-accent/30'}`}>
              {result.rejected ? t('st_rejected') : t(`st_${STEP_KEYS[result.stage]}`)}
            </span>
          </div>

          {/* Progress: one segment per stage, filled up to the current one. */}
          <ol className="grid grid-cols-6 gap-1.5" aria-label="Progress">
            {result.steps.map((step, i) => (
              <li key={step.key} className="min-w-0">
                <div className={`h-1.5 rounded-full ${step.reached ? (i === result.stage ? 'bg-accent' : 'bg-sidebar') : 'bg-line'}`} />
                <p className={`mt-1.5 text-[10px] leading-tight ${i === result.stage ? 'font-bold text-sidebar' : step.reached ? 'text-ink' : 'text-muted'}`}>
                  {t(`st_${step.key}`)}
                </p>
              </li>
            ))}
          </ol>

          {sla && (
            <p className={`flex items-center gap-2 text-xs rounded-lg border px-3 py-2 ${sla.tone}`}>
              {result.status === 'Resolved' || result.status === 'Closed' ? <CheckCircle2 size={14} /> : <Clock3 size={14} />}
              {sla.text}
            </p>
          )}

          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-xs">
            <div><dt className="text-muted">{t('trackFiled')}</dt><dd className="font-semibold text-ink">{formatDate(result.filed_at, lang)}</dd></div>
            <div><dt className="text-muted">{t('trackUpdated')}</dt><dd className="font-semibold text-ink">{formatDate(result.updated_at, lang)}</dd></div>
            {result.category && <div><dt className="text-muted">{t('trackCategory')}</dt><dd className="font-semibold text-ink">{result.category}</dd></div>}
            {result.location.length > 0 && <div><dt className="text-muted">{t('trackPlace')}</dt><dd className="font-semibold text-ink">{result.location.join(', ')}</dd></div>}
          </dl>

          {result.timeline.length > 0 && (
            <div>
              <p className="text-[11px] font-semibold text-muted mb-1.5">{t('trackHistory')}</p>
              <ul className="space-y-1.5 max-h-36 overflow-y-auto pr-1">
                {result.timeline.map((event, i) => (
                  <li key={`${event.at}-${i}`} className="flex items-baseline justify-between gap-3 text-xs">
                    <span className="text-ink">{event.title}</span>
                    <span className="shrink-0 text-muted">{formatDate(event.at, lang)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <button
            type="button"
            onClick={() => { setResult(null); setMobile(''); }}
            className="inline-flex items-center gap-1.5 text-xs font-semibold text-sidebar hover:underline cursor-pointer"
          >
            {t('trackAnother')} <ArrowRight size={13} />
          </button>
        </div>
      )}
    </div>
  );
}
