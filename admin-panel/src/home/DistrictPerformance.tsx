import { useEffect, useState } from 'react';
import { Trophy } from 'lucide-react';
import * as api from '../services/api';
import type { DistrictPerformanceRow } from '../services/api';
import { barWidth, complianceTone, formatCompliance } from './performance';

interface Props {
  t: (key: string, vars?: Record<string, string | number>) => string;
  serif: { fontFamily: string };
}

const BAR: Record<ReturnType<typeof complianceTone>, string> = {
  good: 'bg-emerald-600',
  fair: 'bg-accent',
  poor: 'bg-red-500',
};

/** Top districts by SLA compliance. Renders nothing until at least one district has enough data. */
export default function DistrictPerformance({ t, serif }: Props) {
  const [rows, setRows] = useState<DistrictPerformanceRow[]>([]);
  const [minSample, setMinSample] = useState(3);

  useEffect(() => {
    api.getDistrictPerformance()
      .then((res) => { setRows(res.data.districts); setMinSample(res.data.min_sample); })
      .catch(() => setRows([]));
  }, []);

  if (rows.length === 0) return null;

  return (
    <section id="performance" className="scroll-mt-28 mx-auto max-w-7xl px-4 sm:px-6 py-14">
      <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('perfTag')}</p>
      <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{t('perfTitle')}</h2>
      <p className="mt-3 max-w-2xl text-sm sm:text-base text-muted">{t('perfSub')}</p>

      <ol className="mt-8 divide-y divide-line rounded-2xl border border-line bg-white">
        {rows.map((row) => (
          <li key={row.district} className="grid grid-cols-[2rem_1fr_auto] sm:grid-cols-[2.5rem_1.2fr_2fr_auto] items-center gap-x-4 gap-y-2 px-4 py-4 sm:px-6">
            <span className={`grid h-8 w-8 place-items-center rounded-full text-sm font-bold ${row.rank === 1 ? 'bg-accent text-white' : 'bg-cream text-sidebar'}`}>
              {row.rank === 1 ? <Trophy size={15} aria-label="1" /> : row.rank}
            </span>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-ink">{row.district}</p>
              <p className="text-xs text-muted">{t('perfJudged', { n: row.judged })}</p>
            </div>
            <div className="order-last col-span-3 sm:order-none sm:col-span-1 h-2 rounded-full bg-cream overflow-hidden"
              role="img" aria-label={formatCompliance(row.compliance)}>
              <div className={`h-full rounded-full ${BAR[complianceTone(row.compliance)]}`} style={{ width: barWidth(row.compliance) }} />
            </div>
            <span className="text-right text-lg font-semibold tabular-nums text-sidebar" style={serif}>{formatCompliance(row.compliance)}</span>
          </li>
        ))}
      </ol>
      <p className="mt-3 text-xs text-muted">{t('perfNote', { n: minSample })}</p>
    </section>
  );
}
