import { useEffect, useState } from 'react';
import { ArrowRight } from 'lucide-react';
import * as api from '../services/api';
import type { PublicFunds } from '../services/api';
import type { Lang } from './strings';

interface Props {
  lang: Lang;
  serif: { fontFamily: string };
  onLogin: () => void;
}

type Option = { id: number; name: string };

const COPY = {
  hi: {
    tag: 'पंचायत निधि', title: 'पंचायत का पैसा कहाँ से आया, कहाँ लगा।',
    sub: 'हर ग्राम पंचायत को मिली राशि, उसका खर्च और बची राशि। स्रोत के हिसाब से, हर वित्त वर्ष के लिए।',
    district: 'जिला', block: 'ब्लॉक', panchayat: 'ग्राम पंचायत', fy: 'वित्त वर्ष',
    pickDistrict: 'जिला चुनें', pickBlock: 'ब्लॉक चुनें', pickPanchayat: 'पंचायत चुनें',
    panchayatOf: 'ग्राम पंचायत', fyOf: 'वित्त वर्ष', received: 'कुल प्राप्त', spent: 'खर्च', balance: 'शेष', used: 'उपयोग',
    recent: 'हाल के खर्च', completed: 'पूर्ण', in_progress: 'प्रगति पर', approved: 'स्वीकृत', full: 'पूरा लेखा-जोखा देखने के लिए लॉगिन करें',
    demo: 'डेमो डेटा — असली आँकड़े ई-ग्राम स्वराज / PFMS से जुड़ने के बाद दिखेंगे।',
    loading: 'लोड हो रहा है…', err: 'आँकड़े नहीं मिल सके।', lakh: 'लाख', locale: 'hi-IN',
  },
  en: {
    tag: 'PANCHAYAT FUNDS', title: 'Where the panchayat money came from, and where it went.',
    sub: 'The amount each gram panchayat received, what it spent and what is left. By source, for every financial year.',
    district: 'District', block: 'Block', panchayat: 'Gram panchayat', fy: 'Financial year',
    pickDistrict: 'Select district', pickBlock: 'Select block', pickPanchayat: 'Select panchayat',
    panchayatOf: 'Gram Panchayat', fyOf: 'FY', received: 'Total received', spent: 'Spent', balance: 'Balance', used: 'used',
    recent: 'Recent spending', completed: 'Completed', in_progress: 'In progress', approved: 'Approved', full: 'Log in to see the full accounts',
    demo: 'Demo data — real figures will appear once e-Gram Swaraj / PFMS is connected.',
    loading: 'Loading…', err: 'Could not load the figures.', lakh: 'lakh', locale: 'en-IN',
  },
} as const;

const STATUS_TONE: Record<string, string> = {
  completed: 'bg-emerald-50 text-emerald-700',
  in_progress: 'bg-transparent text-muted',
  approved: 'bg-slate-100 text-slate-600',
};

function financialYears() {
  const now = new Date();
  const start = now.getMonth() >= 3 ? now.getFullYear() : now.getFullYear() - 1;
  return [0, 1, 2].map((i) => `${start - i}-${String(start - i + 1).slice(2)}`);
}

export default function FundsSection({ lang, serif, onLogin }: Props) {
  const c = COPY[lang];
  const years = financialYears();
  const [districts, setDistricts] = useState<Option[]>([]);
  const [blocks, setBlocks] = useState<Option[]>([]);
  const [panchayats, setPanchayats] = useState<Option[]>([]);
  const [districtId, setDistrictId] = useState<number | undefined>();
  const [blockId, setBlockId] = useState<number | undefined>();
  const [panchayatId, setPanchayatId] = useState<number | undefined>();
  const [fy, setFy] = useState(years[0]);
  const [data, setData] = useState<PublicFunds | null>(null);
  const [state, setState] = useState<'idle' | 'loading' | 'error'>('idle');

  // Start on the first district / block / panchayat so the section is never empty.
  useEffect(() => {
    api.getDistricts().then((res) => {
      setDistricts(res.districts);
      setDistrictId(res.districts[0]?.id);
    }).catch(() => {});
  }, []);
  useEffect(() => {
    setBlocks([]); setBlockId(undefined);
    if (!districtId) return;
    api.getPublicBlocks(districtId).then((res) => { setBlocks(res.blocks); setBlockId(res.blocks[0]?.id); }).catch(() => {});
  }, [districtId]);
  useEffect(() => {
    setPanchayats([]); setPanchayatId(undefined);
    if (!blockId) return;
    api.getPublicPanchayats(blockId).then((res) => { setPanchayats(res.panchayats); setPanchayatId(res.panchayats[0]?.id); }).catch(() => {});
  }, [blockId]);

  useEffect(() => {
    if (!panchayatId) { setData(null); return; }
    setState('loading');
    let live = true;
    api.getPublicFunds(panchayatId, fy)
      .then((res) => { if (live) { setData(res.data); setState('idle'); } })
      .catch(() => { if (live) setState('error'); });
    return () => { live = false; };
  }, [panchayatId, fy]);

  const rs = (lakh: number) => `₹${lakh.toLocaleString(c.locale, { maximumFractionDigits: 2 })} ${c.lakh}`;
  const inr = (n: number) => `₹${n.toLocaleString('en-IN')}`;
  const pct = (a: number, b: number) => (b > 0 ? Math.round((a / b) * 100) : 0);
  const fmtDate = (iso: string) => new Intl.DateTimeFormat(c.locale, { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(iso));

  const select = (label: string, value: number | undefined, options: Option[], placeholder: string, onChange: (v?: number) => void) => (
    <label className="text-[11px] font-semibold text-muted">
      {label}
      <select value={value ?? ''} disabled={options.length === 0} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : undefined)}
        className="mt-1 w-full rounded-lg border border-line bg-white px-3 py-3 text-sm text-ink disabled:bg-cream disabled:text-muted">
        <option value="">{placeholder}</option>
        {options.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
      </select>
    </label>
  );

  return (
    <section id="funds" className="scroll-mt-28 mx-auto max-w-7xl px-4 sm:px-6 py-14">
      <div className="grid lg:grid-cols-[1.1fr_1fr] gap-8 items-end">
        <div>
          <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{c.tag}</p>
          <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{c.title}</h2>
          <p className="mt-3 max-w-xl text-sm sm:text-base text-muted">{c.sub}</p>
        </div>
        <div className="grid grid-cols-2 gap-3">
          {select(c.district, districtId, districts, c.pickDistrict, setDistrictId)}
          {select(c.block, blockId, blocks, c.pickBlock, setBlockId)}
          {select(c.panchayat, panchayatId, panchayats, c.pickPanchayat, setPanchayatId)}
          <label className="text-[11px] font-semibold text-muted">
            {c.fy}
            <select value={fy} onChange={(e) => setFy(e.target.value)} className="mt-1 w-full rounded-lg border border-line bg-white px-3 py-3 text-sm text-ink">
              {years.map((y) => <option key={y} value={y}>{y}</option>)}
            </select>
          </label>
        </div>
      </div>

      {state === 'error' && <p className="mt-8 text-sm text-muted">{c.err}</p>}
      {!data && state !== 'error' && <p className="mt-8 text-sm text-muted">{c.loading}</p>}

      {data && (
        <div className={`mt-8 grid lg:grid-cols-[1.6fr_1fr] gap-5 transition-opacity ${state === 'loading' ? 'opacity-60' : ''}`}>
          <div className="rounded-3xl bg-sidebar p-6 sm:p-8 text-white">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h3 className="text-2xl font-semibold" style={serif}>{c.panchayatOf} {data.panchayat}</h3>
              <span className="text-sm text-white/80">{c.fyOf} {data.fy}</span>
            </div>

            <dl className="mt-6 grid grid-cols-3 divide-x divide-white/15 border-y border-white/15">
              {([[c.received, data.received_lakh, ''], [c.spent, data.spent_lakh, ''], [c.balance, data.balance_lakh, 'text-accent']] as const).map(([label, v, tone]) => (
                <div key={label} className="py-4 pl-4 first:pl-0 pr-2">
                  <dt className="text-xs text-white/75">{label}</dt>
                  <dd className={`mt-1 text-xl sm:text-3xl font-semibold tabular-nums ${tone}`} style={serif}>{rs(v)}</dd>
                </div>
              ))}
            </dl>

            <div className="mt-5 h-10 rounded-lg bg-white/10 overflow-hidden" role="img" aria-label={`${pct(data.spent_lakh, data.received_lakh)}% ${c.used}`}>
              <div className="flex h-full items-center bg-accent-dark px-3 text-sm font-semibold" style={{ width: `${Math.max(pct(data.spent_lakh, data.received_lakh), 14)}%` }}>
                {pct(data.spent_lakh, data.received_lakh)}% {c.used}
              </div>
            </div>

            <ul className="mt-5 divide-y divide-white/15">
              {data.sources.map((s) => {
                const p = pct(s.spent_lakh, s.allocated_lakh);
                return (
                  <li key={s.name} className="grid grid-cols-[1fr_auto] sm:grid-cols-[1.2fr_1fr_auto] items-center gap-x-5 gap-y-2 py-3.5">
                    <div className="min-w-0">
                      <p className="text-sm font-semibold">{s.name}</p>
                      <p className="text-xs text-white/65">{s.purpose}</p>
                    </div>
                    <div className="order-3 col-span-2 sm:order-none sm:col-span-1 h-1.5 rounded-full bg-white/15 overflow-hidden">
                      <div className="h-full rounded-full bg-accent" style={{ width: `${p}%` }} />
                    </div>
                    <div className="text-right text-xs">
                      <p className="tabular-nums"><span className="font-semibold">{rs(s.spent_lakh)}</span> <span className="text-white/65">/ {rs(s.allocated_lakh)}</span></p>
                      <p className="text-white/65 tabular-nums">{p}%</p>
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>

          <div className="flex flex-col rounded-3xl border border-line bg-white p-6 sm:p-7">
            <h3 className="text-xl font-semibold text-ink" style={serif}>{c.recent}</h3>
            <ul className="mt-4 flex-1 divide-y divide-line">
              {data.recent.map((r) => (
                <li key={r.title} className="py-4 first:pt-2">
                  <div className="flex items-center justify-between gap-3 text-xs text-muted">
                    <span className={`rounded px-2 py-0.5 font-semibold ${STATUS_TONE[r.status]}`}>{c[r.status]}</span>
                    <span>{fmtDate(r.date)}</span>
                  </div>
                  <p className="mt-1.5 text-sm font-medium text-ink">{r.title}</p>
                  <p className="mt-1 text-xs text-muted"><span className="font-semibold text-ink tabular-nums">{inr(r.amount)}</span> &nbsp; {r.source}</p>
                </li>
              ))}
            </ul>
            <button type="button" onClick={onLogin} className="mt-4 inline-flex items-center justify-center gap-2 rounded-xl bg-sidebar px-5 py-3.5 text-sm font-semibold text-white hover:bg-sidebar-hover cursor-pointer">
              {c.full} <ArrowRight size={15} />
            </button>
          </div>
        </div>
      )}

      {data?.demo && <p className="mt-4 text-xs text-muted">{c.demo}</p>}
    </section>
  );
}
