import { useEffect, useMemo, useState } from 'react';
import { Search, Landmark, Inbox, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react';
import * as api from '../services/api';
import { masterApi } from '../services/api';
import type { MasterPagination } from '../services/api';
import type { Block, District, ElectedRepresentative, ElectedRepresentativeTier, Panchayat } from '../types';

const PAGE_SIZE = 25;

const EMPTY_PAGINATION: MasterPagination = {
  currentPage: 1, lastPage: 1, perPage: PAGE_SIZE, total: 0, from: null, to: null,
};

const TABS: { id: ElectedRepresentativeTier; label: string }[] = [
  { id: 'zp', label: 'Zila Parishad' },
  { id: 'ps', label: 'Panchayat Samiti' },
  { id: 'panch', label: 'Panches' },
];

export default function ElectedRepresentativesPage() {
  const [tier, setTier] = useState<ElectedRepresentativeTier>('zp');
  const [representatives, setRepresentatives] = useState<ElectedRepresentative[]>([]);
  const [pagination, setPagination] = useState<MasterPagination>(EMPTY_PAGINATION);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [districts, setDistricts] = useState<District[]>([]);
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [panchayats, setPanchayats] = useState<Panchayat[]>([]);
  const [panchayatsLoaded, setPanchayatsLoaded] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [districtFilter, setDistrictFilter] = useState('All');
  const [blockFilter, setBlockFilter] = useState('All');
  const [panchayatFilter, setPanchayatFilter] = useState('All');
  const [page, setPage] = useState(1);
  const [refreshKey, setRefreshKey] = useState(0);
  const [error, setError] = useState('');

  const loadPanchayatsOnce = () => {
    if (panchayatsLoaded) return;
    setPanchayatsLoaded(true);
    masterApi('panchayats').list().then(({ items }) => setPanchayats(items)).catch(() => {});
  };

  useEffect(() => {
    masterApi('districts').list().then(({ items }) => setDistricts(items)).catch(() => {});
    masterApi('blocks').list().then(({ items }) => setBlocks(items)).catch(() => {});
  }, []);

  useEffect(() => {
    if (tier === 'panch') loadPanchayatsOnce();
  }, [tier]);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);

    const timer = window.setTimeout(() => {
      api.getElectedRepresentatives({
        tier,
        page,
        perPage: PAGE_SIZE,
        q: searchQuery,
        districtId: districtFilter === 'All' ? undefined : Number(districtFilter),
        blockId: blockFilter === 'All' ? undefined : Number(blockFilter),
        panchayatId: panchayatFilter === 'All' ? undefined : Number(panchayatFilter),
      })
        .then(({ representatives: fetched, pagination: meta, counts: fetchedCounts }) => {
          if (cancelled) return;
          setRepresentatives(fetched);
          setPagination(meta);
          setCounts(fetchedCounts);
          setError('');
        })
        .catch((err) => {
          if (!cancelled) setError((err as Error).message);
        })
        .finally(() => {
          if (!cancelled) setIsLoading(false);
        });
    }, 250);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [tier, page, searchQuery, districtFilter, blockFilter, panchayatFilter, refreshKey]);

  const filterBlocks = useMemo(
    () => (districtFilter === 'All' ? blocks : blocks.filter((b) => String(b.district_id) === districtFilter)),
    [blocks, districtFilter],
  );
  const filterPanchayats = useMemo(
    () => (blockFilter === 'All' ? [] : panchayats.filter((p) => String(p.block_id) === blockFilter)),
    [panchayats, blockFilter],
  );

  const selectTab = (next: ElectedRepresentativeTier) => {
    setTier(next);
    setDistrictFilter('All');
    setBlockFilter('All');
    setPanchayatFilter('All');
    setSearchQuery('');
    setPage(1);
  };

  return (
    <div className="space-y-4">
      {error && (
        <div role="alert" className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2">
          {error}
        </div>
      )}

      <div className="flex items-center gap-1 border-b border-slate-200">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => selectTab(t.id)}
            className={`px-3 py-2 text-xs font-bold border-b-2 -mb-px ${
              tier === t.id ? 'border-accent text-accent' : 'border-transparent text-slate-500 hover:text-slate-700'
            }`}
          >
            {t.label} {counts[t.id] !== undefined && <span className="text-slate-400 font-normal">({counts[t.id]})</span>}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={searchQuery}
            onChange={(e) => { setSearchQuery(e.target.value); setPage(1); }}
            placeholder="Search by name or mobile…"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select
          value={districtFilter}
          onChange={(e) => { setDistrictFilter(e.target.value); setBlockFilter('All'); setPanchayatFilter('All'); setPage(1); }}
          className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
        >
          <option value="All">All Districts</option>
          {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        {tier !== 'zp' && (
          <select
            value={blockFilter}
            onChange={(e) => { setBlockFilter(e.target.value); setPanchayatFilter('All'); setPage(1); }}
            className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white"
          >
            <option value="All">All Blocks</option>
            {filterBlocks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        )}
        {tier === 'panch' && (
          <select
            value={panchayatFilter}
            onChange={(e) => { setPanchayatFilter(e.target.value); setPage(1); }}
            disabled={blockFilter === 'All'}
            title={blockFilter === 'All' ? 'Select a block first' : undefined}
            className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white disabled:bg-slate-50 disabled:text-slate-400"
          >
            <option value="All">All Panchayats</option>
            {filterPanchayats.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        )}
        <button
          type="button"
          onClick={() => setRefreshKey((k) => k + 1)}
          title="Refresh"
          disabled={isLoading}
          className="inline-flex items-center gap-1.5 text-xs font-bold text-slate-700 border border-slate-300 bg-white hover:bg-slate-50 px-3 py-2 rounded-lg cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
        <span className="text-xs text-slate-400 ml-auto flex items-center gap-1.5">
          <Landmark className="w-3.5 h-3.5" />
          {pagination.total} representatives
        </span>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        {isLoading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : representatives.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No representatives match your filters.</p>
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-2.5">S.No.</th>
                <th className="text-left p-2.5">Name</th>
                <th className="text-left p-2.5">Father Name</th>
                <th className="text-left p-2.5">District</th>
                {tier !== 'zp' && <th className="text-left p-2.5">Block</th>}
                {tier === 'panch' && <th className="text-left p-2.5">Panchayat</th>}
                <th className="text-left p-2.5">Ward No.</th>
                <th className="text-left p-2.5">Mobile</th>
                <th className="text-left p-2.5">Gender</th>
              </tr>
            </thead>
            <tbody>
              {representatives.map((r, index) => (
                <tr key={r.id} className="border-t border-slate-100 hover:bg-slate-50">
                  <td className="p-2.5 text-slate-400">{(page - 1) * PAGE_SIZE + index + 1}</td>
                  <td className="p-2.5 font-semibold text-slate-800">{r.name}</td>
                  <td className="p-2.5">{r.father_name || '—'}</td>
                  <td className="p-2.5">{r.district?.name || '—'}</td>
                  {tier !== 'zp' && <td className="p-2.5">{r.block?.name || '—'}</td>}
                  {tier === 'panch' && <td className="p-2.5">{r.panchayat?.name || '—'}</td>}
                  <td className="p-2.5">{r.ward_no || '—'}</td>
                  <td className="p-2.5">{r.mobile || '—'}</td>
                  <td className="p-2.5">{r.gender || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {pagination.total > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {pagination.from ?? 0}–{pagination.to ?? 0} of {pagination.total}</span>
            <div className="flex items-center gap-2">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {pagination.currentPage} of {pagination.lastPage}</span>
              <button onClick={() => setPage((p) => Math.min(pagination.lastPage, p + 1))} disabled={page === pagination.lastPage} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
