import { useEffect, useMemo, useRef, useState } from 'react';
import type MapView from '@arcgis/core/views/MapView.js';
import Graphic from '@arcgis/core/Graphic.js';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer.js';
import Polygon from '@arcgis/core/geometry/Polygon.js';
import Polyline from '@arcgis/core/geometry/Polyline.js';
import type Extent from '@arcgis/core/geometry/Extent.js';
import type { GraphicHit } from '@arcgis/core/views/types.js';
import { Crosshair, Map as MapIcon, Route, Search, Satellite, X } from 'lucide-react';
import ArcGISMap from '../map/ArcGISMap';
import { createStreetsBasemap, createWorldImageryBasemap } from '../map/basemap';
import { dotSymbol } from '../map/symbols';
import { toArcgisXY } from '../map/coords';
import { useLatestRef } from '../map/useLatestRef';
import * as api from '../services/api';
import type { RoadMapFeature, RoadMapResponse } from '../services/api';

const SOURCE_COLOR: Record<string, string> = {
  online: '#16a34a',
  offline_sync: '#f59e0b',
  shp_import: '#7c3aed',
};

const SOURCE_LABEL: Record<string, string> = {
  online: 'Online',
  offline_sync: 'Offline sync',
  shp_import: 'Shapefile import',
};

const HARYANA_CENTER: [number, number] = [29.0588, 76.0856];

function hexToRgb(hex: string): [number, number, number] {
  const clean = hex.replace('#', '');
  return [parseInt(clean.slice(0, 2), 16), parseInt(clean.slice(2, 4), 16), parseInt(clean.slice(4, 6), 16)];
}

function polygonSymbol(color: string, selected: boolean) {
  return {
    type: 'simple-fill' as const,
    color: [...hexToRgb(selected ? '#22d3ee' : color), selected ? 0.35 : 0.28],
    outline: { color: selected ? '#06b6d4' : color, width: selected ? 3.5 : 2 },
  };
}

function formatArea(sqm: number) {
  const hectares = sqm / 10000;
  return `${Math.round(sqm).toLocaleString('en-IN')} m² (${hectares.toLocaleString('en-IN', { maximumFractionDigits: hectares < 1 ? 3 : 2 })} ha)`;
}

function formatDateTime(value: string | null) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(value));
}

const ATTRIBUTE_FIELDS: { key: string; label: string }[] = [
  { key: 'owner_name', label: 'Owner' },
  { key: 'father_name', label: 'Father' },
  { key: 'mobile', label: 'Mobile' },
  { key: 'village', label: 'Village' },
  { key: 'tehsil', label: 'Tehsil' },
  { key: 'district', label: 'District' },
  { key: 'khasra_no', label: 'Khasra no.' },
  { key: 'murabba_no', label: 'Murabba no.' },
  { key: 'crop', label: 'Crop' },
  { key: 'remarks', label: 'Remarks' },
];

const INPUT = 'w-full text-xs border border-line rounded-lg px-3 py-2 bg-white outline-none focus:ring-2 focus:ring-accent/30';

// Bounding extent of some graphics, padded a little so nothing sits on the edge.
function extentOf(graphics: Graphic[]) {
  let extent: Extent | null = null;
  for (const graphic of graphics) {
    const next = graphic.geometry?.extent;
    if (!next) continue;
    extent = extent ? extent.union(next) : next.clone();
  }
  return extent ? extent.expand(1.4) : null;
}

function polygonGeometry(feature: RoadMapFeature) {
  return new Polygon({ rings: feature.geometry.coordinates.map((ring) => ring.map(([lng, lat]) => toArcgisXY(lat, lng))) });
}

export default function RoadMapPage() {
  const [data, setData] = useState<RoadMapResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [query, setQuery] = useState('');
  const [userId, setUserId] = useState('');
  const [source, setSource] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const [view, setView] = useState<MapView | null>(null);
  const [basemap, setBasemap] = useState<'satellite' | 'streets'>('satellite');
  const [selectedUuid, setSelectedUuid] = useState<string | null>(null);
  const [selectedDetail, setSelectedDetail] = useState<RoadMapFeature | null>(null);

  const polygonLayerRef = useRef<GraphicsLayer | null>(null);
  const trackLayerRef = useRef<GraphicsLayer | null>(null);
  const didFitRef = useRef(false);

  const features = useMemo(() => data?.features ?? [], [data]);
  const selected = useMemo(() => features.find((f) => f.properties.uuid === selectedUuid) ?? null, [features, selectedUuid]);
  const featuresRef = useLatestRef(features);

  const filtersActive = query.trim() !== '' || userId !== '' || source !== '' || dateFrom !== '' || dateTo !== '';
  const clearFilters = () => { setQuery(''); setUserId(''); setSource(''); setDateFrom(''); setDateTo(''); };

  // Fetch (debounced) whenever a filter changes.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    const timer = window.setTimeout(() => {
      api.getRoadMapPolygons({ query, userId, source, dateFrom, dateTo })
        .then((response) => { if (!cancelled) setData(response); })
        .catch((err) => { if (!cancelled) setError((err as Error).message); })
        .finally(() => { if (!cancelled) setLoading(false); });
    }, 250);
    return () => { cancelled = true; window.clearTimeout(timer); };
  }, [query, userId, source, dateFrom, dateTo]);

  // A selection that no longer matches the filters is dropped.
  useEffect(() => {
    if (selectedUuid && !features.some((f) => f.properties.uuid === selectedUuid)) {
      setSelectedUuid(null);
      setSelectedDetail(null);
    }
  }, [features, selectedUuid]);

  // Basemap switch.
  useEffect(() => {
    if (!view?.map) return;
    view.map.basemap = basemap === 'streets' ? createStreetsBasemap() : createWorldImageryBasemap();
  }, [view, basemap]);

  // Rebuild the polygon layer (outline + a centre dot so tiny plots stay visible
  // when zoomed out) whenever the data or the selection changes.
  useEffect(() => {
    if (!view?.map) return;
    const graphics: Graphic[] = [];
    for (const feature of features) {
      const color = SOURCE_COLOR[feature.properties.source] ?? '#64748b';
      const isSelected = feature.properties.uuid === selectedUuid;
      const geometry = polygonGeometry(feature);
      graphics.push(new Graphic({ geometry, symbol: polygonSymbol(color, isSelected), attributes: { uuid: feature.properties.uuid } }));
      if (geometry.centroid) {
        graphics.push(new Graphic({
          geometry: geometry.centroid,
          symbol: { ...dotSymbol(isSelected ? '#06b6d4' : color), size: isSelected ? 11 : 8 },
          attributes: { uuid: feature.properties.uuid },
        }));
      }
    }
    const layer = new GraphicsLayer({ graphics });
    if (polygonLayerRef.current) view.map.remove(polygonLayerRef.current);
    view.map.add(layer);
    polygonLayerRef.current = layer;
    // keep the walked track (if any) on top of the freshly added layer
    if (trackLayerRef.current) view.map.reorder(trackLayerRef.current, view.map.layers.length - 1);

    if (!didFitRef.current && graphics.length > 0) {
      didFitRef.current = true;
      const extent = extentOf(graphics);
      if (extent) void view.goTo(extent).catch(() => undefined);
    }
  }, [view, features, selectedUuid]);

  // Selecting a polygon loads its raw walked track and draws it as a dashed line.
  useEffect(() => {
    if (!view?.map) return undefined;
    if (trackLayerRef.current) { view.map.remove(trackLayerRef.current); trackLayerRef.current = null; }
    setSelectedDetail(null);
    if (!selectedUuid) return undefined;

    let cancelled = false;
    api.getRoadMapPolygon(selectedUuid).then((detail) => {
      if (cancelled || !view.map) return;
      setSelectedDetail(detail);
      const track = detail.properties.track;
      if (track && track.coordinates.length > 1) {
        const layer = new GraphicsLayer({
          graphics: [new Graphic({
            geometry: new Polyline({ paths: [track.coordinates.map(([lng, lat]) => toArcgisXY(lat, lng))] }),
            symbol: { type: 'simple-line', color: '#2563eb', width: 2.5, style: 'dash' },
          })],
        });
        view.map.add(layer);
        trackLayerRef.current = layer;
      }
    }).catch(() => undefined);
    return () => { cancelled = true; };
  }, [view, selectedUuid]);

  // Click on the map selects the polygon under the cursor.
  useEffect(() => {
    if (!view) return undefined;
    view.popupEnabled = false;
    const handle = view.on('click', async (event) => {
      const layer = polygonLayerRef.current;
      if (!layer) return;
      const hit = await view.hitTest(event, { include: [layer] });
      const graphicHit = hit.results.find((r): r is GraphicHit => r.type === 'graphic');
      const uuid = graphicHit?.graphic.attributes?.uuid as string | undefined;
      if (uuid && featuresRef.current.some((f) => f.properties.uuid === uuid)) setSelectedUuid(uuid);
    });
    return () => handle.remove();
  }, [view, featuresRef]);

  const zoomTo = (feature: RoadMapFeature) => {
    setSelectedUuid(feature.properties.uuid);
    const extent = polygonGeometry(feature).extent?.expand(2);
    if (view && extent) void view.goTo(extent, { duration: 500 }).catch(() => undefined);
  };

  const fitAll = () => {
    const graphics = polygonLayerRef.current?.graphics.toArray() ?? [];
    const extent = extentOf(graphics);
    if (view && extent) void view.goTo(extent).catch(() => undefined);
  };

  const meta = data?.meta;
  const detail = selectedDetail ?? selected;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Stat label="Polygons" value={meta ? meta.total.toLocaleString('en-IN') : '—'} icon={<Route className="w-4 h-4" />} />
        <Stat label="Total area" value={meta ? formatArea(meta.total_area_sqm) : '—'} icon={<MapIcon className="w-4 h-4" />} />
        <Stat label="Users" value={meta ? String(meta.users) : '—'} icon={<Crosshair className="w-4 h-4" />} />
      </div>

      <div className="bg-white border border-line rounded-xl p-3 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3 items-end">
        <label className="block col-span-2 xl:col-span-2">
          <span className="block text-[10px] font-semibold uppercase tracking-wide text-muted mb-1">Search</span>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted" />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Description, owner, village, khasra, user"
              className={`${INPUT} pl-9`} />
          </div>
        </label>
        <FilterField label="User">
          <select value={userId} onChange={(e) => setUserId(e.target.value)} className={INPUT}>
            <option value="">All users</option>
            {(data?.users ?? []).map((u) => <option key={u.id} value={u.id}>{u.name || u.username} ({u.polygons})</option>)}
          </select>
        </FilterField>
        <FilterField label="Source">
          <select value={source} onChange={(e) => setSource(e.target.value)} className={INPUT}>
            <option value="">All sources</option>
            {Object.entries(SOURCE_LABEL).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </FilterField>
        <FilterField label="Start date">
          <input type="date" value={dateFrom} max={dateTo || undefined} onChange={(e) => setDateFrom(e.target.value)} className={INPUT} />
        </FilterField>
        <FilterField label="End date">
          <input type="date" value={dateTo} min={dateFrom || undefined} onChange={(e) => setDateTo(e.target.value)} className={INPUT} />
        </FilterField>
        <button type="button" onClick={clearFilters} disabled={!filtersActive}
          className="text-xs font-semibold text-accent border border-line rounded-lg px-3 py-2 bg-white hover:bg-cream disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
          Clear filters
        </button>
      </div>

      {error && <p className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">{error}</p>}
      {meta && meta.returned < meta.total && (
        <p className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-3">
          Showing the newest {meta.returned.toLocaleString('en-IN')} of {meta.total.toLocaleString('en-IN')} polygons - narrow the filters to see the rest.
        </p>
      )}

      <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_22rem] gap-4">
        <div className="relative h-[36rem] bg-white border border-line rounded-xl overflow-hidden">
          <ArcGISMap center={HARYANA_CENTER} zoom={7} scrollWheelZoom onViewReady={setView} />

          <div className="absolute top-3 right-3 flex gap-2 z-10">
            <div className="bg-white rounded-lg shadow border border-line p-1 flex">
              <button type="button" onClick={() => setBasemap('satellite')}
                className={`flex items-center gap-1 px-2.5 py-1.5 rounded-md text-[11px] font-semibold cursor-pointer ${basemap === 'satellite' ? 'bg-accent text-white' : 'text-ink hover:bg-cream'}`}>
                <Satellite className="w-3.5 h-3.5" /> Satellite
              </button>
              <button type="button" onClick={() => setBasemap('streets')}
                className={`flex items-center gap-1 px-2.5 py-1.5 rounded-md text-[11px] font-semibold cursor-pointer ${basemap === 'streets' ? 'bg-accent text-white' : 'text-ink hover:bg-cream'}`}>
                <MapIcon className="w-3.5 h-3.5" /> Streets
              </button>
            </div>
            <button type="button" onClick={fitAll} disabled={features.length === 0}
              className="bg-white rounded-lg shadow border border-line px-3 text-[11px] font-semibold text-ink hover:bg-cream disabled:opacity-40 cursor-pointer disabled:cursor-not-allowed">
              Fit to data
            </button>
          </div>

          <div className="absolute bottom-3 left-3 z-10 bg-white/95 rounded-lg shadow border border-line px-3 py-2 text-[11px] space-y-1">
            {Object.entries(SOURCE_LABEL).map(([value, label]) => (
              <div key={value} className="flex items-center gap-2 text-ink">
                <span className="w-3 h-3 rounded-sm border" style={{ background: `${SOURCE_COLOR[value]}55`, borderColor: SOURCE_COLOR[value] }} />
                {label}
              </div>
            ))}
            <div className="flex items-center gap-2 text-ink">
              <span className="w-4 border-t-2 border-dashed" style={{ borderColor: '#2563eb' }} /> Walked path (selected)
            </div>
          </div>

          {loading && <p className="absolute top-3 left-3 z-10 bg-white rounded-lg shadow border border-line px-3 py-1.5 text-xs text-muted">Loading…</p>}
          {!loading && features.length === 0 && !error && (
            <p className="absolute inset-0 z-10 flex items-center justify-center text-sm text-muted pointer-events-none">
              <span className="bg-white/90 border border-line rounded-lg px-4 py-2">No polygons{filtersActive ? ' for the selected filters' : ' saved yet'}.</span>
            </p>
          )}
        </div>

        <div className="bg-white border border-line rounded-xl overflow-hidden flex flex-col h-[36rem]">
          {detail ? (
            <div className="p-4 overflow-y-auto border-b border-line max-h-[60%] shrink-0">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-ink break-words">{detail.properties.description || 'Untitled polygon'}</p>
                  <p className="text-[11px] text-muted mt-0.5">{SOURCE_LABEL[detail.properties.source] ?? detail.properties.source} · {formatDateTime(detail.properties.started_at ?? detail.properties.created_at)}</p>
                </div>
                <button type="button" onClick={() => setSelectedUuid(null)} className="text-muted hover:text-ink cursor-pointer" aria-label="Close details"><X className="w-4 h-4" /></button>
              </div>
              <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 text-[11px]">
                <Detail label="Area" value={formatArea(detail.properties.area_sqm)} wide />
                <Detail label="Perimeter" value={`${Math.round(detail.properties.perimeter_m).toLocaleString('en-IN')} m`} />
                <Detail label="GPS points" value={String(detail.properties.point_count)} />
                <Detail label="Recorded by" value={detail.properties.user ? `${detail.properties.user.name} (${detail.properties.user.role})` : '—'} wide />
                {ATTRIBUTE_FIELDS.filter(({ key }) => detail.properties[key]).map(({ key, label }) => (
                  <Detail key={key} label={label} value={String(detail.properties[key])} />
                ))}
                {Object.entries(detail.properties.extra ?? {}).map(([key, value]) => (
                  <Detail key={`extra-${key}`} label={key.replace(/_/g, ' ')} value={String(value)} />
                ))}
              </dl>
              {!detail.properties.has_data && <p className="text-[11px] text-muted mt-3">No attribute data saved for this polygon yet.</p>}
            </div>
          ) : (
            <p className="px-4 py-3 text-[11px] text-muted border-b border-line shrink-0">Click a polygon on the map or in this list to see its details.</p>
          )}

          <div className="flex-1 overflow-y-auto divide-y divide-line">
            {features.map((feature) => {
              const p = feature.properties;
              const active = p.uuid === selectedUuid;
              return (
                <button key={p.uuid} type="button" onClick={() => zoomTo(feature)}
                  className={`w-full text-left px-4 py-3 cursor-pointer hover:bg-cream/60 ${active ? 'bg-cream' : ''}`}>
                  <div className="flex items-center gap-2">
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: SOURCE_COLOR[p.source] ?? '#64748b' }} />
                    <p className="text-xs font-semibold text-ink truncate">{p.description || p.owner_name || 'Untitled polygon'}</p>
                  </div>
                  <p className="text-[11px] text-muted mt-0.5 pl-4 truncate">
                    {formatArea(p.area_sqm)} · {p.user?.name ?? 'Unknown'}{p.village ? ` · ${p.village}` : ''}
                  </p>
                </button>
              );
            })}
            {!loading && features.length === 0 && <p className="p-4 text-xs text-muted">Nothing to list.</p>}
          </div>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value, icon }: { label: string; value: string; icon: React.ReactNode }) {
  return (
    <div className="bg-white border border-line rounded-xl p-4 flex items-center gap-3">
      <div className="w-9 h-9 rounded-lg bg-accent-soft text-accent flex items-center justify-center">{icon}</div>
      <div><p className="text-lg font-semibold text-ink leading-tight">{value}</p><p className="text-[11px] text-muted">{label}</p></div>
    </div>
  );
}

function FilterField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-[10px] font-semibold uppercase tracking-wide text-muted mb-1">{label}</span>
      {children}
    </label>
  );
}

function Detail({ label, value, wide }: { label: string; value: string; wide?: boolean }) {
  return (
    <div className={wide ? 'col-span-2' : ''}>
      <dt className="text-[10px] uppercase tracking-wide text-muted">{label}</dt>
      <dd className="text-ink break-words">{value}</dd>
    </div>
  );
}
