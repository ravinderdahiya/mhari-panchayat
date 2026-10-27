import { Bell, ClipboardCheck, FileSearch, Landmark, Megaphone, ShieldCheck, Smartphone } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useInView } from './hooks';

type T = (key: string, vars?: Record<string, string | number>) => string;

interface Props {
  t: T;
  serif: { fontFamily: string };
  androidUrl: string | null;
  iosUrl: string | null;
}

const BASE = import.meta.env.BASE_URL;

// Geometry of the feature chain, in px. Each bubble sits on a gentle arc; the
// dotted line is drawn through the centres of the round icons.
const ROW = 80;
const ICON = 48;
const OFFSETS = [6, 52, 84, 80, 46, 4];
const WIDTH = 340;

interface Feature {
  key: string;
  icon: LucideIcon;
  pill: string;
  ring: string;
  tone: string;
}

const FEATURES: Feature[] = [
  { key: 'appF1', icon: Megaphone, pill: 'bg-emerald-50', ring: 'border-emerald-400', tone: 'text-emerald-600' },
  { key: 'appF2', icon: FileSearch, pill: 'bg-sky-50', ring: 'border-sky-400', tone: 'text-sky-600' },
  { key: 'appF3', icon: Landmark, pill: 'bg-amber-50', ring: 'border-amber-400', tone: 'text-amber-600' },
  { key: 'appF4', icon: ClipboardCheck, pill: 'bg-orange-50', ring: 'border-orange-400', tone: 'text-orange-600' },
  { key: 'appF5', icon: ShieldCheck, pill: 'bg-indigo-50', ring: 'border-indigo-400', tone: 'text-indigo-600' },
  { key: 'appF6', icon: Bell, pill: 'bg-rose-50', ring: 'border-rose-400', tone: 'text-rose-600' },
];

/** Smooth curve through the points (Catmull-Rom converted to cubic Beziers). */
function smoothPath(points: [number, number][]) {
  let d = `M ${points[0][0]} ${points[0][1]}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[i - 1] ?? points[i];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[i + 2] ?? p2;
    const c1: [number, number] = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2: [number, number] = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C ${c1[0]} ${c1[1]}, ${c2[0]} ${c2[1]}, ${p2[0]} ${p2[1]}`;
  }
  return d;
}

export default function AppShowcase({ t, serif, androidUrl, iosUrl }: Props) {
  const [ref, seen] = useInView<HTMLDivElement>('0px 0px -15% 0px');

  const centres: [number, number][] = FEATURES.map((_, i) => [OFFSETS[i] + 4 + ICON / 2, i * ROW + ROW / 2]);
  const path = smoothPath(centres);

  return (
    <section id="download" className="scroll-mt-28 bg-white border-y border-line overflow-hidden">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 py-16">
        <div className="max-w-2xl">
          <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('appTag')}</p>
          <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{t('appTitle')}</h2>
          <p className="mt-3 text-sm sm:text-base text-muted">{t('appShowSub')}</p>
          <div className="mt-6 flex flex-wrap gap-3">
            {androidUrl && (
              <a href={androidUrl} target="_blank" rel="noreferrer"
                className="inline-flex items-center gap-2 rounded-lg bg-sidebar px-5 py-3 text-sm font-semibold text-white hover:bg-sidebar-hover">
                <Smartphone size={16} /> {t('playBtn')}
              </a>
            )}
            {iosUrl ? (
              <a href={iosUrl} target="_blank" rel="noreferrer"
                className="inline-flex items-center gap-2 rounded-lg bg-sidebar px-5 py-3 text-sm font-semibold text-white hover:bg-sidebar-hover">
                <Smartphone size={16} /> {t('iosBtn')}
              </a>
            ) : (
              <span className="inline-flex items-center gap-2 rounded-lg border border-line bg-white px-5 py-3 text-sm text-muted">{t('iosSoon')}</span>
            )}
          </div>
        </div>

        <div ref={ref} className="mt-12 grid lg:grid-cols-2 items-center gap-12 lg:gap-6">
          {/* Phone showing the real app */}
          <div className="relative mx-auto">
            <div aria-hidden className="absolute left-1/2 top-1/2 -z-0 h-[26rem] w-[26rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent-soft/50 blur-3xl" />
            <div className="relative w-[14.5rem] sm:w-[16rem] rounded-[2.7rem] bg-[#16181b] p-[0.55rem] shadow-[0_40px_70px_-30px_rgba(22,51,44,0.65)] ring-1 ring-black/20">
              <span aria-hidden className="absolute -left-[3px] top-24 h-9 w-[3px] rounded-l bg-[#16181b]" />
              <span aria-hidden className="absolute -left-[3px] top-36 h-14 w-[3px] rounded-l bg-[#16181b]" />
              <span aria-hidden className="absolute -right-[3px] top-32 h-16 w-[3px] rounded-r bg-[#16181b]" />
              <div className="relative overflow-hidden rounded-[2.2rem] bg-white" style={{ aspectRatio: '851 / 1847' }}>
                <img src={`${BASE}images/app-preview.jpg`} alt={t('appPreviewAlt')} loading="lazy" className="h-full w-full object-cover object-top" />
                <span aria-hidden className="absolute left-1/2 top-2.5 h-[1.15rem] w-20 -translate-x-1/2 rounded-full bg-black" />
              </div>
            </div>
          </div>

          {/* Feature chain on a dotted arc */}
          <div className="mx-auto" style={{ width: WIDTH, maxWidth: '100%' }}>
            <div className="relative" style={{ height: FEATURES.length * ROW }}>
              <svg aria-hidden className="absolute inset-0 h-full w-full" viewBox={`0 0 ${WIDTH} ${FEATURES.length * ROW}`} fill="none">
                <path d={path} stroke="#C68A16" strokeOpacity="0.75" strokeWidth="2" strokeLinecap="round" strokeDasharray="1 7" />
              </svg>
              <ul className="relative">
                {FEATURES.map(({ key, icon: Icon, pill, ring, tone }, i) => (
                  <li
                    key={key}
                    className={`absolute transition-all duration-700 ease-out motion-reduce:transition-none ${seen ? 'translate-x-0 opacity-100' : 'translate-x-8 opacity-0'}`}
                    style={{ left: OFFSETS[i], top: i * ROW + (ROW - 56) / 2, transitionDelay: `${i * 110}ms` }}
                  >
                    <div className={`flex h-14 items-center gap-3 rounded-full pl-1 pr-6 shadow-sm ${pill}`}>
                      <span className={`grid shrink-0 place-items-center rounded-full border-2 border-dashed bg-white ${ring} ${tone}`} style={{ width: ICON, height: ICON }}>
                        <Icon size={20} />
                      </span>
                      <span className="text-[13px] font-semibold leading-tight text-ink">{t(key)}</span>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
