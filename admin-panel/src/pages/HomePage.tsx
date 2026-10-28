import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import {
  ArrowRight, ArrowUp, BarChart3, Check, ClipboardCheck, Clock, FileText, FileSearch, Building2,
  HardHat, Hammer, Landmark, LogIn, Mail, MapPin, Megaphone, Menu, Phone, Search,
  UserRound, Users, X, ChevronDown, Contrast, Construction, Waves, Droplets, Zap, Lightbulb, Trash2, ShieldAlert, Ellipsis,
} from 'lucide-react';
import * as api from '../services/api';
import type { PublicHome, PublicPanchayatHit } from '../services/api';
import TrackCard from '../home/TrackCard';
import AppShowcase from '../home/AppShowcase';
import type { MapFilters } from '../home/HomeMap';
import { translator, type Lang } from '../home/strings';
import { useCountUp, useInView, usePersistentState } from '../home/hooks';

// The map pulls in the whole ArcGIS SDK, so it is only fetched when its section nears the viewport.
const HomeMap = lazy(() => import('../home/HomeMap'));

interface Props {
  onLogin: () => void;
}

const LANGS = ['hi', 'en'] as const;
const SCALES = ['sm', 'md', 'lg'] as const;
const SCALE_PX: Record<(typeof SCALES)[number], string> = { sm: '15px', md: '16px', lg: '18px' };
const BASE = import.meta.env.BASE_URL;

function Stat({ label, value, decimals = 0, suffix = '', start, noData, loading }: {
  label: string; value: number | null; decimals?: number; suffix?: string; start: boolean; noData: string; loading: boolean;
}) {
  const shown = useCountUp(value, start, 1400, decimals);
  return (
    <div className="px-5 py-5 sm:px-6">
      <p className="font-serif text-3xl sm:text-4xl font-semibold text-sidebar tabular-nums">
        {loading ? <span className="inline-block h-8 w-24 rounded bg-line/70 animate-pulse align-middle" aria-hidden />
          : value === null ? <span className="text-xl text-muted font-sans font-medium">{noData}</span>
          : <>{shown.toLocaleString('en-IN', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}{suffix}</>}
      </p>
      <p className="mt-1 text-xs sm:text-sm text-muted">{label}</p>
    </div>
  );
}

export default function HomePage({ onLogin }: Props) {
  const [lang, setLang] = usePersistentState<Lang>('home_lang', 'hi', LANGS);
  const [scale, setScale] = usePersistentState<(typeof SCALES)[number]>('home_scale', 'md', SCALES);
  const t = useMemo(() => translator(lang), [lang]);
  const serif = { fontFamily: lang === 'hi' ? "'Noto Serif Devanagari', 'Fraunces', serif" : "'Fraunces', serif" };

  // Whole-page text size (the A- A A+ buttons): rem units follow the root font size.
  useEffect(() => {
    const root = document.documentElement;
    const previous = root.style.fontSize;
    root.style.fontSize = SCALE_PX[scale];
    return () => { root.style.fontSize = previous; };
  }, [scale]);

  const [contrast, setContrast] = usePersistentState<'off' | 'on'>('home_contrast', 'off', ['off', 'on'] as const);
  useEffect(() => {
    const root = document.documentElement;
    root.classList.toggle('home-contrast', contrast === 'on');
    return () => root.classList.remove('home-contrast');
  }, [contrast]);

  useEffect(() => { document.documentElement.lang = lang === 'hi' ? 'hi' : 'en'; }, [lang]);

  // ---- live data (refreshed every 5 minutes while the page stays open) ----
  const [home, setHome] = useState<PublicHome | null>(null);
  const [loadError, setLoadError] = useState(false);
  const loadHome = useCallback(() => {
    api.getPublicHome()
      .then((res) => { setHome(res.data); setLoadError(false); })
      .catch(() => setLoadError(true));
  }, []);
  useEffect(() => {
    loadHome();
    const timer = window.setInterval(loadHome, 5 * 60 * 1000);
    return () => window.clearInterval(timer);
  }, [loadHome]);

  // ---- navigation ----
  const [menuOpen, setMenuOpen] = useState(false);
  const [showTop, setShowTop] = useState(false);
  useEffect(() => {
    const onScroll = () => setShowTop(window.scrollY > 600);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);
  const go = (id: string) => {
    setMenuOpen(false);
    const el = document.getElementById(id);
    if (!el) return;
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
  };

  const trackFromLink = useMemo(() => new URLSearchParams(window.location.search).get('track') ?? undefined, []);
  useEffect(() => { if (trackFromLink) window.setTimeout(() => go('track'), 300); }, [trackFromLink]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- header search (panchayat type-ahead) ----
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<PublicPanchayatHit[]>([]);
  const [searchOpen, setSearchOpen] = useState(false);
  const [searched, setSearched] = useState(false);
  useEffect(() => {
    if (query.trim().length < 2) { setHits([]); setSearched(false); return undefined; }
    const timer = window.setTimeout(() => {
      api.searchPublicPanchayats(query.trim())
        .then((res) => { setHits(res.data); setSearched(true); })
        .catch(() => { setHits([]); setSearched(true); });
    }, 250);
    return () => window.clearTimeout(timer);
  }, [query]);

  // ---- map area filters (district -> block -> panchayat) ----
  const [filters, setFilters] = useState<MapFilters>({});
  const [districts, setDistricts] = useState<{ id: number; name: string }[]>([]);
  const [blocks, setBlocks] = useState<{ id: number; name: string }[]>([]);
  const [panchayats, setPanchayats] = useState<{ id: number; name: string }[]>([]);
  useEffect(() => { api.getDistricts().then((res) => setDistricts(res.districts)).catch(() => {}); }, []);

  const loadBlocks = (districtId?: number) => {
    if (!districtId) { setBlocks([]); return Promise.resolve([] as { id: number; name: string }[]); }
    return api.getPublicBlocks(districtId).then((res) => { setBlocks(res.blocks); return res.blocks; }).catch(() => []);
  };
  const loadPanchayats = (blockId?: number) => {
    if (!blockId) { setPanchayats([]); return Promise.resolve(); }
    return api.getPublicPanchayats(blockId).then((res) => setPanchayats(res.panchayats)).catch(() => {});
  };
  const pickDistrict = (id?: number) => { setFilters({ district_id: id }); setPanchayats([]); void loadBlocks(id); };
  const pickBlock = (id?: number) => { setFilters((f) => ({ district_id: f.district_id, block_id: id })); void loadPanchayats(id); };
  const pickPanchayat = (id?: number) => setFilters((f) => ({ district_id: f.district_id, block_id: f.block_id, panchayat_id: id }));

  const choosePanchayat = async (hit: PublicPanchayatHit) => {
    setSearchOpen(false);
    setQuery(hit.name);
    setFilters({ district_id: hit.district_id ?? undefined, block_id: hit.block_id ?? undefined, panchayat_id: hit.id });
    await Promise.all([loadBlocks(hit.district_id ?? undefined), loadPanchayats(hit.block_id ?? undefined)]);
    go('assets');
  };

  // ---- scroll-triggered bits ----
  const [statsRef, statsSeen] = useInView<HTMLDivElement>('0px 0px -10% 0px');
  const [mapRef, mapNear] = useInView<HTMLDivElement>('300px');

  const nav = [
    ['home', t('nHome')], ['journey', t('nAbout')], ['download', t('nFile')],
    ['track', t('nTrack')], ['assets', t('nAssets')], ['services', t('nServices')], ['download', t('nDownloads')],
  ] as const;

  const stats = home?.stats;
  const roles = [
    { icon: UserRound, title: t('roleCitizen'), sub: t('roleCitizenSub'), tone: 'bg-emerald-50 text-emerald-800' },
    { icon: FileText, title: t('roleSachiv'), sub: t('roleSachivSub'), tone: 'bg-amber-50 text-amber-800' },
    { icon: MapPin, title: t('roleCplo'), sub: t('roleCploSub'), tone: 'bg-sky-50 text-sky-800' },
    { icon: Building2, title: t('roleBdpo'), sub: t('roleBdpoSub'), tone: 'bg-orange-50 text-orange-800' },
  ];

  const journey = ['j1', 'j2', 'j3', 'j4', 'j5', 'j6'];
  const services: { icon: typeof FileText; key: string; action?: () => void; soon?: boolean }[] = [
    { icon: Megaphone, key: 'svc1', action: () => go('download') },
    { icon: FileSearch, key: 'svc2', action: () => go('track') },
    { icon: Landmark, key: 'svc3', action: () => go('assets') },
    { icon: ClipboardCheck, key: 'svc4', action: () => go('assets') },
    { icon: Users, key: 'svc5', soon: true },
    { icon: Hammer, key: 'svc6', soon: true },
    { icon: BarChart3, key: 'svc7', action: onLogin },
    { icon: HardHat, key: 'svc8', action: onLogin },
  ];

  const ann = home?.announcement;
  const [cat, setCat] = useState<string | null>(null);
  const categories: [string, typeof Zap][] = [
    ['catGali', Construction], ['catNaali', Waves], ['catPaani', Droplets], ['catBijli', Zap],
    ['catLight', Lightbulb], ['catSafai', Trash2], ['catAtikraman', ShieldAlert], ['catOther', Ellipsis],
  ];
  const pick = (en: string, hi: string) => (lang === 'hi' && hi ? hi : en);

  return (
    <div className="min-h-screen bg-cream text-ink" style={{ fontFamily: lang === 'hi' ? "'Noto Sans Devanagari','IBM Plex Sans',sans-serif" : undefined }}>
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:z-50 focus:left-3 focus:top-3 focus:bg-white focus:px-3 focus:py-2 focus:rounded focus:shadow">
        {t('skip')}
      </a>

      {/* Government strip */}
      <div className="bg-white border-b border-line text-[11px] sm:text-xs">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 h-9 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-muted min-w-0">
            <img src={`${BASE}images/haryana-emblem.svg`} alt="" className="h-4 w-auto" />
            <span className="font-medium text-ink truncate">{t('govt')}</span>
            <span className="hidden sm:inline text-line">|</span>
            <span className="hidden sm:inline truncate">{t('dept')}</span>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button type="button" onClick={() => setContrast(contrast === 'on' ? 'off' : 'on')} aria-pressed={contrast === 'on'} title={t('contrast')} aria-label={t('contrast')}
              className={`rounded border border-line px-2 py-0.5 cursor-pointer ${contrast === 'on' ? 'bg-sidebar text-white' : 'bg-white text-ink hover:bg-cream'}`}><Contrast size={13} /></button>
            <div className="flex items-center rounded border border-line overflow-hidden" role="group" aria-label="Text size">
              {SCALES.map((s, i) => (
                <button key={s} type="button" onClick={() => setScale(s)} aria-pressed={scale === s}
                  className={`px-2 py-0.5 cursor-pointer ${scale === s ? 'bg-sidebar text-white' : 'bg-white text-ink hover:bg-cream'}`}
                  style={{ fontSize: `${10 + i * 2}px` }}>
                  A{i === 0 ? '-' : i === 2 ? '+' : ''}
                </button>
              ))}
            </div>
            <div className="flex items-center rounded border border-line overflow-hidden" role="group" aria-label="Language">
              {LANGS.map((l) => (
                <button key={l} type="button" onClick={() => setLang(l)} aria-pressed={lang === l}
                  className={`px-2.5 py-0.5 font-semibold cursor-pointer ${lang === l ? 'bg-sidebar text-white' : 'bg-white text-ink hover:bg-cream'}`}>
                  {l === 'hi' ? 'हिंदी' : 'English'}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Header */}
      <header className="bg-white border-b border-line sticky top-0 z-40">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 h-16 flex items-center gap-4">
          <button type="button" onClick={() => go('home')} className="flex items-center gap-3 min-w-0 cursor-pointer text-left">
            <span className="grid place-items-center h-10 w-10 rounded-full bg-sidebar text-white shrink-0"><Landmark size={20} /></span>
            <span className="min-w-0">
              <span className="block text-lg leading-tight font-semibold text-sidebar truncate" style={serif}>{t('appName')}</span>
              <span className="hidden sm:block text-[11px] text-muted truncate">{t('appSub')}</span>
            </span>
          </button>

          <div className="relative ml-auto hidden md:block w-80 lg:w-96">
            <div className="flex">
              <input
                value={query}
                onChange={(e) => { setQuery(e.target.value); setSearchOpen(true); }}
                onFocus={() => setSearchOpen(true)}
                onBlur={() => window.setTimeout(() => setSearchOpen(false), 150)}
                placeholder={t('search')}
                aria-label={t('search')}
                className="w-full rounded-l-lg border border-line bg-cream/50 px-3 py-2 text-sm outline-none focus:border-sidebar"
              />
              <button type="button" onClick={() => hits[0] && void choosePanchayat(hits[0])}
                className="inline-flex items-center gap-1.5 rounded-r-lg bg-sidebar px-4 text-sm font-semibold text-white hover:bg-sidebar-hover cursor-pointer">
                <Search size={15} /> {t('searchBtn')}
              </button>
            </div>
            {searchOpen && query.trim().length >= 2 && (hits.length > 0 || searched) && (
              <ul className="absolute z-50 mt-1 w-full rounded-lg border border-line bg-white shadow-lg overflow-hidden">
                {hits.length === 0 ? (
                  <li className="px-3 py-2.5 text-sm text-muted">{t('searchNone')}</li>
                ) : hits.map((hit) => (
                  <li key={hit.id}>
                    <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => void choosePanchayat(hit)}
                      className="w-full text-left px-3 py-2 text-sm hover:bg-cream cursor-pointer">
                      <span className="font-semibold text-ink">{hit.name}</span>
                      <span className="block text-xs text-muted">{[hit.block, hit.district].filter(Boolean).join(' · ')}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <button type="button" onClick={onLogin}
            className="ml-auto md:ml-0 inline-flex items-center gap-2 rounded-lg border border-sidebar px-4 py-2 text-sm font-semibold text-sidebar hover:bg-sidebar hover:text-white cursor-pointer">
            <LogIn size={16} /> {t('login')}
          </button>
          <button type="button" className="md:hidden p-2 -mr-2 cursor-pointer" aria-label="Menu" aria-expanded={menuOpen} onClick={() => setMenuOpen((o) => !o)}>
            {menuOpen ? <X size={22} /> : <Menu size={22} />}
          </button>
        </div>

        {/* Primary nav */}
        <nav className={`bg-sidebar text-white ${menuOpen ? 'block' : 'hidden'} md:block`} aria-label="Primary">
          <ul className="mx-auto max-w-7xl px-4 sm:px-6 flex flex-col md:flex-row md:items-center md:gap-1 py-2 md:py-0 text-sm">
            {nav.map(([id, label], i) => (
              <li key={`${id}-${i}`}>
                <button type="button" onClick={() => go(id)}
                  className={`w-full text-left px-3 md:px-4 py-2.5 md:py-3 cursor-pointer hover:bg-sidebar-hover ${i === 0 ? 'bg-sidebar-active font-semibold' : ''}`}>
                  {label}
                </button>
              </li>
            ))}
            <li className="md:hidden px-3 py-2">
              <input value={query} onChange={(e) => { setQuery(e.target.value); setSearchOpen(true); }} placeholder={t('search')}
                className="w-full rounded-lg px-3 py-2 text-sm text-ink outline-none" />
              {query.trim().length >= 2 && hits.length > 0 && (
                <ul className="mt-1 rounded-lg bg-white text-ink overflow-hidden">
                  {hits.map((hit) => (
                    <li key={hit.id}><button type="button" onClick={() => void choosePanchayat(hit)} className="w-full text-left px-3 py-2 text-sm hover:bg-cream">
                      {hit.name} <span className="text-xs text-muted">· {hit.block}, {hit.district}</span>
                    </button></li>
                  ))}
                </ul>
              )}
            </li>
          </ul>
        </nav>
      </header>

      {ann && (
        <div className="bg-accent-soft/60 border-b border-accent/20 text-xs sm:text-sm" role="status">
          <div className="mx-auto max-w-7xl px-4 sm:px-6 py-1.5 flex items-center gap-3 min-w-0">
            <span className="shrink-0 rounded bg-accent-dark px-2 py-0.5 text-[10px] font-bold tracking-wide text-white">{t('tickerLabel')}</span>
            <span className="truncate text-ink">{pick(ann.title, ann.title_hi)}</span>
            {ann.cta_url && (
              <a href={ann.cta_url} target={ann.cta_url.startsWith('http') ? '_blank' : undefined} rel="noreferrer" className="ml-auto shrink-0 font-semibold text-sidebar hover:underline">
                {pick(ann.cta_label, ann.cta_label_hi) || '→'}
              </a>
            )}
          </div>
        </div>
      )}

      <main id="main">
        {/* Hero + tracker */}
        <section id="home" className="relative overflow-hidden scroll-mt-28">
          <div aria-hidden className="pointer-events-none absolute -right-24 -top-24 h-[28rem] w-[28rem] rounded-full border border-accent/20" />
          <div aria-hidden className="pointer-events-none absolute -right-8 -top-8 h-[20rem] w-[20rem] rounded-full border border-accent/20" />
          <div className="relative mx-auto max-w-7xl px-4 sm:px-6 py-10 lg:py-16 grid lg:grid-cols-[1.15fr_1fr] gap-10 items-center">
            <div>
              <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('eyebrow')}</p>
              <h1 className="mt-4 text-4xl sm:text-5xl lg:text-[3.4rem] leading-[1.15] font-semibold text-sidebar" style={serif}>
                {t('h1a')}<br /><span className="text-accent-dark">{t('h1b')}</span>
              </h1>
              <p className="mt-5 text-lg italic text-ink/80" style={serif}>{t('lead')}</p>
              <p className="mt-4 max-w-xl text-sm sm:text-base text-muted leading-relaxed">{t('sub')}</p>
              <div className="mt-7 flex flex-wrap gap-3">
                <button type="button" onClick={() => go('download')}
                  className="inline-flex items-center gap-2 rounded-lg bg-sidebar px-5 py-3 text-sm font-semibold text-white hover:bg-sidebar-hover cursor-pointer">
                  <Megaphone size={16} /> {t('ctaFile')}
                </button>
                <button type="button" onClick={() => go('track')}
                  className="inline-flex items-center gap-2 rounded-lg border border-line bg-white px-5 py-3 text-sm font-semibold text-sidebar hover:border-sidebar cursor-pointer">
                  {t('ctaTrack')} <ArrowRight size={16} />
                </button>
              </div>
              <ul className="mt-6 flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
                {['tick1', 'tick2', 'tick3'].map((k) => (
                  <li key={k} className="inline-flex items-center gap-1.5"><Check size={14} className="text-status-closed" /> {t(k)}</li>
                ))}
              </ul>
            </div>
            <TrackCard t={t} lang={lang} initialId={trackFromLink} />
          </div>
        </section>

        {/* Quick complaint categories */}
        <section className="mx-auto max-w-7xl px-4 sm:px-6 -mt-2 mb-8">
          <p className="text-sm font-semibold text-sidebar" style={serif}>{t('catTitle')}</p>
          <div className="mt-3 grid grid-cols-4 lg:grid-cols-8 gap-2">
            {categories.map(([key, Icon]) => (
              <button key={key} type="button" onClick={() => setCat(key)} aria-pressed={cat === key}
                className={`flex flex-col items-center gap-1.5 rounded-xl border px-2 py-3 text-xs font-semibold cursor-pointer transition ${cat === key ? 'border-sidebar bg-sidebar text-white' : 'border-line bg-white text-ink hover:border-sidebar'}`}>
                <Icon size={20} /> {t(key)}
              </button>
            ))}
          </div>
          {cat && (
            <div className="mt-3 flex flex-wrap items-center gap-3 rounded-xl bg-accent-soft/60 px-4 py-3 text-sm text-ink">
              <span>{t('catHint', { c: t(cat) })}</span>
              <button type="button" onClick={() => go('download')} className="ml-auto inline-flex items-center gap-1.5 font-semibold text-sidebar hover:underline cursor-pointer">{t('ctaFile')} <ArrowRight size={14} /></button>
            </div>
          )}
        </section>

        {/* Who it is for */}
        <section className="mx-auto max-w-7xl px-4 sm:px-6 -mt-2">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            {roles.map(({ icon: Icon, title, sub, tone }) => (
              <button key={title} type="button" onClick={onLogin}
                className="group flex items-center gap-3 rounded-xl border border-line bg-white p-4 text-left hover:border-sidebar hover:shadow-md transition cursor-pointer">
                <span className={`grid place-items-center h-10 w-10 rounded-lg shrink-0 ${tone}`}><Icon size={18} /></span>
                <span className="min-w-0">
                  <span className="block text-sm font-semibold text-ink truncate">{title}</span>
                  <span className="block text-xs text-muted truncate">{sub}</span>
                </span>
              </button>
            ))}
          </div>
        </section>

        {/* Live numbers */}
        <section className="mx-auto max-w-7xl px-4 sm:px-6 mt-8">
          <div ref={statsRef} className="grid grid-cols-2 lg:grid-cols-4 divide-x divide-y lg:divide-y-0 divide-line rounded-xl border border-line bg-white overflow-hidden">
            <Stat label={t('statPanchayats')} value={stats?.panchayats ?? null} start={statsSeen} noData={t('statNoData')} loading={!home && !loadError} />
            <Stat label={t('statResolved')} value={stats?.complaints_resolved || null} start={statsSeen} noData={t('statTrial')} loading={!home && !loadError} />
            <Stat label={t('statDays')} value={stats?.complaints_resolved ? stats.avg_resolution_days : null} decimals={1} start={statsSeen} noData={t('statTrial')} loading={!home && !loadError} />
            <Stat label={t('statAssets')} value={stats?.assets_geotagged ?? null} start={statsSeen} noData={t('statNoData')} loading={!home && !loadError} />
          </div>
          {loadError && !home && (
            <p className="mt-3 text-xs text-muted">
              {t('loadErr')} <button type="button" onClick={loadHome} className="font-semibold text-sidebar underline cursor-pointer">{t('retry')}</button>
            </p>
          )}
        </section>

        {/* Complaint journey */}
        <section id="journey" className="scroll-mt-28 mt-14 bg-cream border-y border-line">
          <div className="mx-auto max-w-7xl px-4 sm:px-6 py-14">
            <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('journeyTag')}</p>
            <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar max-w-2xl leading-tight" style={serif}>{t('journeyTitle')}</h2>
            <p className="mt-3 max-w-2xl text-sm sm:text-base text-muted">{t('journeySub')}</p>

            <ol className="mt-8 grid sm:grid-cols-2 lg:grid-cols-6 gap-3">
              {journey.map((k, i) => (
                <li key={k} className="rounded-xl border border-line bg-white p-4">
                  <span className={`inline-grid place-items-center h-7 w-7 rounded-lg text-xs font-bold ${i === 3 ? 'bg-accent text-white' : 'bg-sidebar text-white'}`}>{`0${i + 1}`}</span>
                  <p className="mt-3 text-sm font-semibold text-ink">{t(k)}</p>
                  <p className="mt-1 text-xs text-muted leading-relaxed">{t(`${k}d`)}</p>
                </li>
              ))}
            </ol>

            <div className="mt-5 flex flex-wrap items-center gap-2 rounded-xl bg-sidebar px-4 py-3 text-white text-sm">
              <span className="inline-flex items-center gap-2 font-semibold"><Clock size={16} className="text-accent" /> {t('slaTitle')}</span>
              {['esc1', 'esc2', 'esc3', 'esc4'].map((k, i) => (
                <span key={k} className="inline-flex items-center gap-2">
                  {i > 0 && <ArrowRight size={14} className="text-accent" />}
                  <span className="rounded-full border border-white/25 px-3 py-0.5 text-xs">{t(k)}</span>
                </span>
              ))}
            </div>
          </div>
        </section>

        {/* Services */}
        <section id="services" className="scroll-mt-28 mx-auto max-w-7xl px-4 sm:px-6 py-14">
          <div className="flex items-end justify-between gap-4">
            <div>
              <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('svcTag')}</p>
              <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{t('svcTitle')}</h2>
            </div>
            <button type="button" onClick={onLogin} className="hidden sm:inline-flex items-center gap-1.5 text-sm font-semibold text-sidebar hover:underline cursor-pointer">
              {t('svcAll')} <ArrowRight size={15} />
            </button>
          </div>
          <div className="mt-8 grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
            {services.map(({ icon: Icon, key, action, soon }) => (
              <button key={key} type="button" onClick={action} disabled={!action}
                className={`relative text-left rounded-xl border border-line bg-white p-5 transition ${action ? 'hover:border-sidebar hover:shadow-md cursor-pointer' : 'opacity-70 grayscale cursor-default'}`}>
                {soon && <span className="absolute right-3 top-3 text-[10px] font-semibold text-accent-dark bg-accent-soft/60 rounded-full px-2 py-0.5">{t('soon')}</span>}
                <Icon size={20} className="text-sidebar" />
                <p className="mt-3 text-sm font-semibold text-ink">{t(key)}</p>
                <p className="mt-1 text-xs text-muted leading-relaxed">{t(`${key}d`, { n: home?.asset_types.total ?? '' })}</p>
              </button>
            ))}
          </div>
        </section>

        {/* Asset map */}
        <section id="assets" ref={mapRef as React.RefObject<HTMLElement>} className="scroll-mt-28 bg-white border-y border-line">
          <div className="mx-auto max-w-7xl px-4 sm:px-6 py-14 grid lg:grid-cols-[1fr_1.2fr] gap-10">
            <div>
              <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('mapTag')}</p>
              <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{t('mapTitle')}</h2>
              <p className="mt-3 text-sm sm:text-base text-muted">{t('mapSub')}</p>
              {home && home.asset_types.featured.length > 0 && (
                <div className="mt-6">
                  <p className="text-[11px] font-semibold tracking-wide text-muted">{t('legendTitle')}</p>
                  <ul className="mt-2 divide-y divide-line rounded-xl border border-line bg-cream/40">
                    {home.asset_types.featured.map((a) => (
                      <li key={a.name} className="flex items-center justify-between gap-3 px-4 py-2 text-sm">
                        <span className="inline-flex items-center gap-2 text-ink"><span aria-hidden className="h-2.5 w-2.5 rounded-full bg-accent" />{lang === 'hi' && a.name_hi ? a.name_hi : a.name}</span>
                        <span className="font-semibold tabular-nums text-sidebar">{a.count.toLocaleString('en-IN')}</span>
                      </li>
                    ))}
                    {home.asset_types.total > home.asset_types.featured.length && (
                      <li className="px-4 py-2 text-xs font-semibold text-accent-dark">{t('more', { n: home.asset_types.total - home.asset_types.featured.length })}</li>
                    )}
                  </ul>
                </div>
              )}
              <button type="button" onClick={onLogin} className="mt-6 inline-flex items-center gap-2 rounded-lg bg-sidebar px-5 py-3 text-sm font-semibold text-white hover:bg-sidebar-hover cursor-pointer">
                {t('mapOpen')} <ArrowRight size={16} />
              </button>
            </div>

            <div className="flex flex-col gap-3">
              <div className="grid grid-cols-3 gap-2">
                <label className="text-[11px] font-semibold text-muted">
                  {t('fDistrict')}
                  <select value={filters.district_id ?? ''} onChange={(e) => pickDistrict(e.target.value ? Number(e.target.value) : undefined)}
                    className="mt-1 w-full rounded-lg border border-line bg-white px-2 py-2 text-sm text-ink">
                    <option value="">{t('fAll')}</option>
                    {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </label>
                <label className="text-[11px] font-semibold text-muted">
                  {t('fBlock')}
                  <select value={filters.block_id ?? ''} disabled={blocks.length === 0} onChange={(e) => pickBlock(e.target.value ? Number(e.target.value) : undefined)}
                    className="mt-1 w-full rounded-lg border border-line bg-white px-2 py-2 text-sm text-ink disabled:bg-cream disabled:text-muted">
                    <option value="">{t('fSelectBlock')}</option>
                    {blocks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                  </select>
                </label>
                <label className="text-[11px] font-semibold text-muted">
                  {t('fPanchayat')}
                  <select value={filters.panchayat_id ?? ''} disabled={panchayats.length === 0} onChange={(e) => pickPanchayat(e.target.value ? Number(e.target.value) : undefined)}
                    className="mt-1 w-full rounded-lg border border-line bg-white px-2 py-2 text-sm text-ink disabled:bg-cream disabled:text-muted">
                    <option value="">{t('fSelectPanchayat')}</option>
                    {panchayats.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </label>
              </div>
              <div className="h-[26rem]">
                {mapNear ? (
                  <Suspense fallback={<div className="grid h-full place-items-center rounded-2xl border border-line bg-cream text-sm text-muted">{t('mapLoading')}</div>}>
                    <HomeMap t={t} lang={lang} filters={filters} />
                  </Suspense>
                ) : (
                  <div className="grid h-full place-items-center rounded-2xl border border-line bg-cream text-sm text-muted">{t('mapLoading')}</div>
                )}
              </div>
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className="scroll-mt-28 mx-auto max-w-4xl px-4 sm:px-6 py-14">
          <p className="text-[11px] font-semibold tracking-[0.14em] text-accent-dark">{t('faqTag')}</p>
          <h2 className="mt-3 text-3xl sm:text-4xl font-semibold text-sidebar leading-tight" style={serif}>{t('faqTitle')}</h2>
          <div className="mt-6 space-y-2">
            {['faq1', 'faq2', 'faq3', 'faq4'].map((k) => (
              <details key={k} className="group rounded-xl border border-line bg-white px-5 py-3">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-sm font-semibold text-ink">
                  {t(k + 'q')} <ChevronDown size={16} className="shrink-0 text-muted transition group-open:rotate-180" />
                </summary>
                <p className="mt-2 text-sm text-muted leading-relaxed">{t(k + 'a')}</p>
              </details>
            ))}
          </div>
        </section>

        {/* Dynamic announcement (set by an admin) */}
        {ann && (
          <section className="mx-auto max-w-7xl px-4 sm:px-6 mt-14">
            <div className="rounded-2xl bg-accent-dark px-6 py-7 sm:px-10 sm:py-9 text-white flex flex-wrap items-center justify-between gap-5">
              <div className="min-w-0 max-w-3xl">
                {pick(ann.tag, ann.tag_hi) && <p className="text-[11px] font-semibold tracking-[0.14em] opacity-80">{pick(ann.tag, ann.tag_hi)}</p>}
                <h2 className="mt-2 text-2xl sm:text-3xl font-semibold leading-snug" style={serif}>{pick(ann.title, ann.title_hi)}</h2>
                {pick(ann.body, ann.body_hi) && <p className="mt-2 text-sm opacity-90">{pick(ann.body, ann.body_hi)}</p>}
              </div>
              {ann.cta_url && (
                <a href={ann.cta_url} target={ann.cta_url.startsWith('http') ? '_blank' : undefined} rel="noreferrer"
                  className="inline-flex items-center gap-2 rounded-lg bg-white px-5 py-3 text-sm font-semibold text-sidebar hover:bg-cream">
                  {pick(ann.cta_label, ann.cta_label_hi) || t('retry')} <ArrowRight size={16} />
                </a>
              )}
            </div>
          </section>
        )}

        <AppShowcase t={t} serif={serif} androidUrl={home?.app.android_url ?? null} iosUrl={home?.app.ios_url ?? null} />
      </main>

      {/* Footer */}
      <footer className="bg-sidebar text-white/85">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 py-12 grid sm:grid-cols-2 lg:grid-cols-[1.4fr_1fr_1fr_1fr] gap-8 text-sm">
          <div>
            <p className="text-xl font-semibold text-white" style={serif}>{t('appName')}</p>
            <p className="mt-3 max-w-xs text-xs leading-relaxed text-white/70">{t('fAbout')}</p>
          </div>
          <div>
            <p className="text-[11px] font-semibold tracking-wide text-white/60">{t('fQuick')}</p>
            <ul className="mt-3 space-y-2">
              <li><button type="button" onClick={() => go('download')} className="hover:underline cursor-pointer">{t('nFile')}</button></li>
              <li><button type="button" onClick={() => go('track')} className="hover:underline cursor-pointer">{t('nTrack')}</button></li>
              <li><button type="button" onClick={() => go('assets')} className="hover:underline cursor-pointer">{t('nAssets')}</button></li>
              <li><button type="button" onClick={onLogin} className="hover:underline cursor-pointer">{t('login')}</button></li>
            </ul>
          </div>
          <div>
            <p className="text-[11px] font-semibold tracking-wide text-white/60">{t('fHelp')}</p>
            <ul className="mt-3 space-y-2">
              {home?.contact.helpline && <li className="flex items-center gap-2"><Phone size={14} /> <a href={`tel:${home.contact.helpline.replace(/\s/g, '')}`} className="hover:underline">{home.contact.helpline}</a></li>}
              {home?.contact.email && <li className="flex items-center gap-2"><Mail size={14} /> <a href={`mailto:${home.contact.email}`} className="hover:underline break-all">{home.contact.email}</a></li>}
              <li className="flex items-start gap-2"><MapPin size={14} className="mt-0.5 shrink-0" /> {t('fAddress')}</li>
              <li className="flex items-center gap-2"><Clock size={14} /> {home?.contact.office_hours || t('fHoursDefault')}</li>
                          </ul>
          </div>
          <div>
            <p className="text-[11px] font-semibold tracking-wide text-white/60">{t('fPolicies')}</p>
            <ul className="mt-3 space-y-2">
              <li><a href={`${BASE}privacy-policy.html`} className="hover:underline">{t('fPrivacy')}</a></li>
              <li><a href={`${BASE}terms-of-service.html`} className="hover:underline">{t('fTerms')}</a></li>
            </ul>
          </div>
        </div>
        <div className="border-t border-white/10">
          <div className="mx-auto max-w-7xl px-4 sm:px-6 py-4 flex flex-wrap items-center justify-between gap-2 text-[11px] text-white/60">
            <p>{t('fOwner')}</p>
            <p>{home ? `${t('fUpdated')}: ${new Intl.DateTimeFormat(lang === 'hi' ? 'hi-IN' : 'en-IN', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(home.generated_at))}` : ''}</p>
          </div>
        </div>
      </footer>

      {showTop && (
        <button type="button" onClick={() => go('home')} aria-label={t('top')}
          className="fixed bottom-5 right-5 z-40 grid h-11 w-11 place-items-center rounded-full bg-sidebar text-white shadow-lg hover:bg-sidebar-hover cursor-pointer">
          <ArrowUp size={18} />
        </button>
      )}
    </div>
  );
}
