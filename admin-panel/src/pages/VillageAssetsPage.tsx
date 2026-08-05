import { useEffect, useMemo, useRef, useState } from 'react';
import type MapView from '@arcgis/core/views/MapView.js';
import Graphic from '@arcgis/core/Graphic.js';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer.js';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer.js';
import UniqueValueRenderer from '@arcgis/core/renderers/UniqueValueRenderer.js';
import Extent from '@arcgis/core/geometry/Extent.js';
import Polyline from '@arcgis/core/geometry/Polyline.js';
import Polygon from '@arcgis/core/geometry/Polygon.js';
import type { GraphicHit } from '@arcgis/core/views/types.js';
import ArcGISMap from '../map/ArcGISMap';
import { dotSymbol, lineSymbolFor, fillSymbolFor } from '../map/symbols';
import { toArcgisPoint, toArcgisXY } from '../map/coords';
import { useLatestRef } from '../map/useLatestRef';
import {
  Search, MapPin, Plus, X, Trash2, Undo2, Inbox, ChevronLeft, ChevronRight, Crosshair, PenLine,
} from 'lucide-react';
import * as api from '../services/api';
import { masterApi } from '../services/api';
import type { VillageAsset, AssetCategoryDef, Village, AssetGeometryType } from '../types';

// Fixed, known category set (see MasterDataController::ASSET_CATEGORIES) — a static
// lookup is more stable/auditable than a runtime hash, and a UniqueValueRenderer needs
// an explicit map like this anyway.
const CATEGORY_COLORS: Record<string, string> = {
  'Roads & Connectivity': '#2a78d6',
  'Water Infrastructure': '#008300',
  'Drainage & Sanitation': '#e87ba4',
  'Electricity & Lighting': '#eda100',
  'Community Buildings': '#1baf7a',
  'Religious & Public Places': '#eb6834',
  'Recreation & Sports': '#4a3aa7',
  'Agriculture-related Assets': '#e34948',
  'Waste Management': '#c026d3',
  'Boundary & Administrative': '#0891b2',
};
const DEFAULT_CATEGORY_COLOR = '#64748b';
function categoryColor(name: string): string {
  return CATEGORY_COLORS[name] ?? DEFAULT_CATEGORY_COLOR;
}

const STATUS_STYLES: Record<string, string> = {
  Working: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  'Not Working': 'bg-red-100 text-red-700 border-red-200',
  'Under Construction': 'bg-amber-100 text-amber-700 border-amber-200',
};
const CONDITION_STYLES: Record<string, string> = {
  Good: 'bg-status-closed/10 text-status-closed border-status-closed/25',
  Fair: 'bg-amber-100 text-amber-700 border-amber-200',
  Poor: 'bg-red-100 text-red-700 border-red-200',
};

const PAGE_SIZE = 10;
const DEFAULT_CENTER: [number, number] = [29.0588, 76.0856];

interface DraftState {
  category: string;
  subtype: string;
  geometryType: AssetGeometryType;
  assetName: string;
  villageId: string;
  wardNo: string;
  status: string;
  condition: string;
  installedDate: string;
  lastInspected: string;
  remarks: string;
}

const EMPTY_DRAFT: DraftState = {
  category: '', subtype: '', geometryType: 'Point', assetName: '', villageId: '',
  wardNo: '', status: 'Working', condition: 'Good', installedDate: '', lastInspected: '', remarks: '',
};

export default function VillageAssetsPage() {
  const [assets, setAssets] = useState<VillageAsset[]>([]);
  const [categories, setCategories] = useState<AssetCategoryDef[]>([]);
  const [villages, setVillages] = useState<Village[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState('All');
  const [villageFilter, setVillageFilter] = useState('All');
  const [page, setPage] = useState(1);

  const [selected, setSelected] = useState<VillageAsset | null>(null);
  const [isAdding, setIsAdding] = useState(false);
  const [draft, setDraft] = useState<DraftState>(EMPTY_DRAFT);
  const [editFields, setEditFields] = useState<Partial<DraftState>>({});
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [actionError, setActionError] = useState('');

  const [placingPoint, setPlacingPoint] = useState(false);
  const [drawingPath, setDrawingPath] = useState(false);
  const [tempLat, setTempLat] = useState<number | null>(null);
  const [tempLng, setTempLng] = useState<number | null>(null);
  const [tempPath, setTempPath] = useState<[number, number][]>([]);

  const load = async () => {
    setIsLoading(true);
    try {
      const { assets } = await api.getVillageAssets();
      setAssets(assets);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    load();
    api.getAssetCategories().then(({ categories }) => setCategories(categories)).catch(() => {});
    masterApi('villages').list().then(({ items }) => setVillages(items)).catch(() => {});
  }, []);

  useEffect(() => { setPage(1); }, [searchQuery, categoryFilter, statusFilter, villageFilter]);

  const filtered = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return assets
      .filter((a) => categoryFilter === 'All' || a.category === categoryFilter)
      .filter((a) => statusFilter === 'All' || a.status === statusFilter)
      .filter((a) => villageFilter === 'All' || a.village_id === Number(villageFilter))
      .filter((a) => !q || [a.asset_name, a.subtype, a.category].join(' ').toLowerCase().includes(q));
  }, [assets, searchQuery, categoryFilter, statusFilter, villageFilter]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const pointAssets = filtered.filter((a) => a.geometry_type === 'Point' && a.latitude != null && a.longitude != null);
  const lineAssets = filtered.filter((a) => a.geometry_type === 'Line' && a.path && a.path.length >= 2);
  const polygonAssets = filtered.filter((a) => a.geometry_type === 'Polygon' && a.path && a.path.length >= 2);

  const allPointsForBounds: [number, number][] = [
    ...pointAssets.map((a) => [a.latitude!, a.longitude!] as [number, number]),
    ...lineAssets.flatMap((a) => a.path!),
    ...polygonAssets.flatMap((a) => a.path!),
  ];
  const mapCenter = allPointsForBounds[0] ?? DEFAULT_CENTER;

  const subtypesForCategory = categories.find((c) => c.category === draft.category)?.subtypes ?? [];

  const resetGeometryCapture = () => {
    setPlacingPoint(false);
    setDrawingPath(false);
    setTempLat(null);
    setTempLng(null);
    setTempPath([]);
  };

  const startAdd = () => {
    setSelected(null);
    setIsAdding(true);
    setDraft(EMPTY_DRAFT);
    setPhotoFile(null);
    resetGeometryCapture();
    setActionError('');
  };

  const cancelAdd = () => {
    setIsAdding(false);
    resetGeometryCapture();
  };

  const selectCategory = (category: string) => {
    const catDef = categories.find((c) => c.category === category);
    const firstSubtype = catDef?.subtypes[0];
    setDraft((d) => ({ ...d, category, subtype: firstSubtype?.name ?? '', geometryType: firstSubtype?.geometryType ?? 'Point' }));
    resetGeometryCapture();
  };

  const selectSubtype = (subtypeName: string) => {
    const subtypeDef = subtypesForCategory.find((s) => s.name === subtypeName);
    setDraft((d) => ({ ...d, subtype: subtypeName, geometryType: subtypeDef?.geometryType ?? d.geometryType }));
    resetGeometryCapture();
  };

  const setGeometryType = (g: AssetGeometryType) => {
    setDraft((d) => ({ ...d, geometryType: g }));
    resetGeometryCapture();
  };

  const handleMapClick = (lat: number, lng: number) => {
    if (placingPoint) {
      setTempLat(lat);
      setTempLng(lng);
      setPlacingPoint(false);
    } else if (drawingPath) {
      setTempPath((p) => [...p, [lat, lng]]);
    }
  };

  const selectAsset = (asset: VillageAsset) => {
    setIsAdding(false);
    resetGeometryCapture();
    setSelected(asset);
    setEditFields({
      assetName: asset.asset_name,
      villageId: String(asset.village_id),
      wardNo: asset.ward_no != null ? String(asset.ward_no) : '',
      status: asset.status,
      condition: asset.condition,
      installedDate: asset.installed_date ?? '',
      lastInspected: asset.last_inspected ?? '',
      remarks: asset.remarks ?? '',
    });
    setPhotoFile(null);
    setActionError('');
  };

  const [view, setView] = useState<MapView | null>(null);
  const pointLayerRef = useRef<FeatureLayer | null>(null);
  const lineLayerRef = useRef<GraphicsLayer | null>(null);
  const polygonLayerRef = useRef<GraphicsLayer | null>(null);
  const previewLayerRef = useRef<GraphicsLayer | null>(null);

  const modeRef = useLatestRef({ isAdding, placingPoint, drawingPath });
  const handleMapClickRef = useLatestRef(handleMapClick);
  const selectAssetRef = useLatestRef(selectAsset);
  const filteredRef = useLatestRef(filtered);

  // Single persistent click handler: capture-mode clicks place points/vertices;
  // otherwise hit-test existing shapes to select them. The capture branch always
  // returns before any hit-testing runs, so a click on an existing shape while
  // drawing can never also select it and cancel the in-progress draft — the bug
  // the old Leaflet version had (map-level and shape-level clicks both firing).
  useEffect(() => {
    if (!view) return undefined;
    view.popupEnabled = false;
    const handle = view.on('click', async (event) => {
      const mode = modeRef.current;
      if (mode.isAdding && (mode.placingPoint || mode.drawingPath)) {
        event.stopPropagation();
        const { latitude, longitude } = event.mapPoint;
        if (latitude == null || longitude == null) return;
        handleMapClickRef.current(latitude, longitude);
        return;
      }
      const layers = [pointLayerRef.current, lineLayerRef.current, polygonLayerRef.current]
        .filter((l): l is FeatureLayer | GraphicsLayer => l != null);
      if (!layers.length) return;
      const hit = await view.hitTest(event, { include: layers });
      const graphicHit = hit.results.find((r): r is GraphicHit => r.type === 'graphic');
      const assetId = graphicHit?.graphic.attributes?.assetId;
      if (assetId == null) return;
      const asset = filteredRef.current.find((a) => a.id === assetId);
      if (!asset) return;
      selectAssetRef.current(asset);
      if (graphicHit!.graphic.layer === pointLayerRef.current && view.popup) {
        view.openPopup({ features: [graphicHit!.graphic] });
      }
    });
    return () => handle.remove();
  }, [view, modeRef, handleMapClickRef, selectAssetRef, filteredRef]);

  // Rebuild the points/lines/polygons layers whenever the filtered set changes.
  useEffect(() => {
    if (!view?.map) return;

    const pointGraphics = pointAssets.map((a) => new Graphic({
      geometry: toArcgisPoint(a.latitude!, a.longitude!),
      attributes: {
        id: a.id, assetId: a.id, category: a.category, subtype: a.subtype, status: a.status, assetName: a.asset_name,
      },
    }));
    const pointLayer = new FeatureLayer({
      source: pointGraphics,
      objectIdField: 'id',
      geometryType: 'point',
      fields: [
        { name: 'id', type: 'oid' },
        { name: 'assetId', type: 'integer' },
        { name: 'category', type: 'string' },
        { name: 'subtype', type: 'string' },
        { name: 'status', type: 'string' },
        { name: 'assetName', type: 'string' },
      ],
      featureReduction: { type: 'cluster', clusterRadius: '80px' },
      renderer: new UniqueValueRenderer({
        field: 'category',
        defaultSymbol: dotSymbol(DEFAULT_CATEGORY_COLOR),
        uniqueValueInfos: Object.entries(CATEGORY_COLORS).map(([category, color]) => ({ value: category, symbol: dotSymbol(color) })),
      }),
      popupTemplate: { title: '{assetName}', content: '{category} — {subtype}<br />{status}' },
    });

    const lineLayer = new GraphicsLayer({
      graphics: lineAssets.map((a) => new Graphic({
        geometry: new Polyline({ paths: [a.path!.map(([lat, lng]) => toArcgisXY(lat, lng))] }),
        symbol: lineSymbolFor(categoryColor(a.category)),
        attributes: { assetId: a.id },
      })),
    });

    const polygonLayer = new GraphicsLayer({
      graphics: polygonAssets.map((a) => new Graphic({
        geometry: new Polygon({ rings: [a.path!.map(([lat, lng]) => toArcgisXY(lat, lng))] }),
        symbol: fillSymbolFor(categoryColor(a.category)),
        attributes: { assetId: a.id },
      })),
    });

    if (pointLayerRef.current) view.map.remove(pointLayerRef.current);
    if (lineLayerRef.current) view.map.remove(lineLayerRef.current);
    if (polygonLayerRef.current) view.map.remove(polygonLayerRef.current);
    view.map.addMany([pointLayer, lineLayer, polygonLayer]);
    pointLayerRef.current = pointLayer;
    lineLayerRef.current = lineLayer;
    polygonLayerRef.current = polygonLayer;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, pointAssets, lineAssets, polygonAssets]);

  // Live orange dashed preview while adding a new asset.
  useEffect(() => {
    if (!view?.map) return;
    let previewLayer = previewLayerRef.current;
    if (!previewLayer) {
      previewLayer = new GraphicsLayer();
      view.map.add(previewLayer);
      previewLayerRef.current = previewLayer;
    }
    previewLayer.removeAll();
    if (!isAdding) return;

    if (draft.geometryType === 'Point' && tempLat != null && tempLng != null) {
      previewLayer.add(new Graphic({ geometry: toArcgisPoint(tempLat, tempLng), symbol: dotSymbol('#f97316') }));
    } else if (draft.geometryType === 'Line' && tempPath.length >= 2) {
      previewLayer.add(new Graphic({
        geometry: new Polyline({ paths: [tempPath.map(([lat, lng]) => toArcgisXY(lat, lng))] }),
        symbol: lineSymbolFor('#f97316', { dashed: true }),
      }));
    } else if (draft.geometryType === 'Polygon' && tempPath.length >= 3) {
      previewLayer.add(new Graphic({
        geometry: new Polygon({ rings: [tempPath.map(([lat, lng]) => toArcgisXY(lat, lng))] }),
        symbol: fillSymbolFor('#f97316', { dashed: true }),
      }));
    }
  }, [view, isAdding, draft.geometryType, tempLat, tempLng, tempPath]);

  // Reframe the view on the filtered set — suppressed entirely during add-mode
  // (matches the old FitBounds being unmounted while isAdding).
  useEffect(() => {
    if (!view || isAdding || allPointsForBounds.length === 0) return;
    const xy = allPointsForBounds.map(([lat, lng]) => toArcgisXY(lat, lng));
    const xs = xy.map(([x]) => x);
    const ys = xy.map(([, y]) => y);
    const extent = new Extent({
      xmin: Math.min(...xs), xmax: Math.max(...xs),
      ymin: Math.min(...ys), ymax: Math.max(...ys),
      spatialReference: { wkid: 4326 },
    }).expand(1.2);
    void view.goTo({ target: extent }, { duration: 300 })
      .then(() => { if (view.zoom > 15) return view.goTo({ zoom: 15 }); })
      .catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, isAdding, allPointsForBounds]);

  const canSaveNew = !!(
    draft.category && draft.subtype && draft.assetName.trim() && draft.villageId &&
    (draft.geometryType === 'Point' ? tempLat != null && tempLng != null : tempPath.length >= 2)
  );

  const saveNew = async () => {
    setIsSubmitting(true);
    setActionError('');
    try {
      const form = new FormData();
      form.append('village_id', draft.villageId);
      form.append('category', draft.category);
      form.append('subtype', draft.subtype);
      form.append('asset_name', draft.assetName.trim());
      form.append('geometry_type', draft.geometryType);
      if (draft.geometryType === 'Point') {
        form.append('latitude', String(tempLat));
        form.append('longitude', String(tempLng));
      } else {
        form.append('path', JSON.stringify(tempPath));
      }
      form.append('status', draft.status);
      form.append('condition', draft.condition);
      if (draft.wardNo) form.append('ward_no', draft.wardNo);
      if (draft.installedDate) form.append('installed_date', draft.installedDate);
      if (draft.lastInspected) form.append('last_inspected', draft.lastInspected);
      if (draft.remarks) form.append('remarks', draft.remarks);
      if (photoFile) form.append('photo', photoFile);

      const { asset } = await api.createVillageAsset(form);
      setAssets((prev) => [asset, ...prev]);
      setIsAdding(false);
      resetGeometryCapture();
      selectAsset(asset);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const saveEdit = async () => {
    if (!selected) return;
    setIsSubmitting(true);
    setActionError('');
    try {
      const form = new FormData();
      form.append('asset_name', editFields.assetName ?? '');
      form.append('village_id', editFields.villageId ?? '');
      form.append('status', editFields.status ?? '');
      form.append('condition', editFields.condition ?? '');
      if (editFields.wardNo) form.append('ward_no', editFields.wardNo);
      if (editFields.installedDate) form.append('installed_date', editFields.installedDate);
      if (editFields.lastInspected) form.append('last_inspected', editFields.lastInspected);
      form.append('remarks', editFields.remarks ?? '');
      if (photoFile) form.append('photo', photoFile);

      const { asset } = await api.updateVillageAsset(selected.id, form);
      setAssets((prev) => prev.map((a) => (a.id === asset.id ? asset : a)));
      setSelected(asset);
      setPhotoFile(null);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const deleteAsset = async () => {
    if (!selected) return;
    if (!confirm(`Delete "${selected.asset_name}"? This cannot be undone.`)) return;
    setIsSubmitting(true);
    try {
      await api.deleteVillageAsset(selected.id);
      setAssets((prev) => prev.filter((a) => a.id !== selected.id));
      setSelected(null);
    } catch (err) {
      setActionError((err as Error).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const uniqueCategoriesInData = useMemo(() => Array.from(new Set(assets.map((a) => a.category))).sort(), [assets]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
          <input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search assets…"
            className="w-full text-xs border border-slate-300 rounded-lg pl-8 pr-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent"
          />
        </div>
        <select value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Categories</option>
          {uniqueCategoriesInData.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Statuses</option>
          <option value="Working">Working</option>
          <option value="Not Working">Not Working</option>
          <option value="Under Construction">Under Construction</option>
        </select>
        <select value={villageFilter} onChange={(e) => setVillageFilter(e.target.value)} className="text-xs border border-slate-300 rounded-lg px-2.5 py-2 bg-white">
          <option value="All">All Villages</option>
          {villages.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
        </select>
        <button
          onClick={startAdd}
          className="flex items-center gap-1.5 text-xs font-bold px-3 py-2 rounded-lg bg-accent hover:bg-accent-dark text-white ml-auto"
        >
          <Plus className="w-3.5 h-3.5" />
          Add Asset
        </button>
      </div>

      {error && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{error}</p>}

      <div className="bg-white border border-slate-200 rounded-2xl p-5">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-bold text-slate-500 uppercase flex items-center gap-1.5">
            <MapPin className="w-3.5 h-3.5" />
            Asset Map
          </h3>
          <span className="text-xs text-slate-400">{filtered.length} assets shown</span>
        </div>

        {isAdding && (
          <div className="mb-3 flex items-center gap-2 text-xs font-semibold text-status-closed bg-status-closed/10 border border-status-closed/25 rounded-lg px-3 py-2">
            {draft.geometryType === 'Point' ? (
              <>
                <Crosshair className="w-3.5 h-3.5" />
                {placingPoint ? 'Click anywhere on the map to place the pin…' : (tempLat != null ? `Pin set: ${tempLat.toFixed(5)}, ${tempLng!.toFixed(5)}` : 'Click "Place Pin" below, then click the map.')}
              </>
            ) : (
              <>
                <PenLine className="w-3.5 h-3.5" />
                {drawingPath ? `Drawing… ${tempPath.length} point(s) added, click map to add more.` : `${tempPath.length} point(s) captured.`}
              </>
            )}
          </div>
        )}

        <div className="h-[26rem] rounded-xl overflow-hidden">
          <ArcGISMap center={mapCenter} zoom={13} scrollWheelZoom onViewReady={setView} />
        </div>
        {allPointsForBounds.length === 0 && !isAdding && (
          <p className="text-xs text-slate-400 mt-2">No assets with location data match the current filters.</p>
        )}
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl overflow-x-auto">
        {isLoading ? (
          <p className="text-sm text-slate-400 p-6">Loading…</p>
        ) : filtered.length === 0 ? (
          <div className="p-10 text-center">
            <Inbox className="w-6 h-6 text-slate-300 mx-auto mb-2" />
            <p className="text-sm text-slate-400">No assets match your filters.</p>
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-slate-50 text-slate-500 uppercase text-[10px]">
                <th className="text-left p-3 font-bold">Asset Name</th>
                <th className="text-left p-3 font-bold">Category / Subtype</th>
                <th className="text-left p-3 font-bold">Village</th>
                <th className="text-left p-3 font-bold">Status</th>
                <th className="text-left p-3 font-bold">Condition</th>
                <th className="text-left p-3 font-bold">Ward</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((a, idx) => (
                <tr
                  key={a.id}
                  onClick={() => selectAsset(a)}
                  className={`border-t border-slate-100 cursor-pointer transition-colors hover:bg-accent/5 ${
                    selected?.id === a.id ? 'bg-accent/10' : idx % 2 === 1 ? 'bg-slate-50/60' : 'bg-white'
                  }`}
                >
                  <td className="p-3 font-semibold text-slate-800">{a.asset_name}</td>
                  <td className="p-3">
                    <span className="flex items-center gap-2 text-slate-600">
                      <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: categoryColor(a.category) }} />
                      {a.category} <span className="text-slate-300">/</span> {a.subtype}
                    </span>
                  </td>
                  <td className="p-3 text-slate-500">{a.village?.name ?? '—'}</td>
                  <td className="p-3"><span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${STATUS_STYLES[a.status]}`}>{a.status}</span></td>
                  <td className="p-3"><span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full border ${CONDITION_STYLES[a.condition]}`}>{a.condition}</span></td>
                  <td className="p-3 text-slate-400">{a.ward_no ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-3 py-2.5 border-t border-slate-100 text-xs text-slate-500">
            <span>Showing {(page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length}</span>
            <div className="flex items-center gap-2">
              <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                <ChevronLeft className="w-3.5 h-3.5" />
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages} className="flex items-center gap-1 px-2 py-1 rounded-lg border border-slate-200 disabled:opacity-40">
                Next
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        )}
      </div>

      {isAdding && (
        <div className="bg-white border border-slate-200 rounded-2xl p-5 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-bold text-slate-900">Add Village Asset</h2>
            <button onClick={cancelAdd} className="text-slate-400 hover:text-slate-600"><X className="w-4 h-4" /></button>
          </div>

          {actionError && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{actionError}</p>}

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Category</label>
              <select value={draft.category} onChange={(e) => selectCategory(e.target.value)} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option value="">Select category…</option>
                {categories.map((c) => <option key={c.category} value={c.category}>{c.category}</option>)}
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Subtype</label>
              <select value={draft.subtype} onChange={(e) => selectSubtype(e.target.value)} disabled={!draft.category} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 disabled:bg-slate-50">
                <option value="">Select subtype…</option>
                {subtypesForCategory.map((s) => <option key={s.name} value={s.name}>{s.name}</option>)}
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Geometry Type</label>
              <div className="flex gap-1">
                {(['Point', 'Line', 'Polygon'] as AssetGeometryType[]).map((g) => (
                  <button
                    key={g}
                    onClick={() => setGeometryType(g)}
                    className={`flex-1 text-[11px] font-bold px-2 py-1.5 rounded-lg border transition-colors ${
                      draft.geometryType === g ? 'bg-accent text-white border-accent' : 'bg-white text-slate-500 border-slate-200'
                    }`}
                  >
                    {g}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="bg-slate-50 border border-slate-100 rounded-xl p-3">
            {draft.geometryType === 'Point' ? (
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setPlacingPoint(true)}
                  className={`flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-lg border ${placingPoint ? 'bg-orange-500 text-white border-orange-500' : 'bg-white text-slate-600 border-slate-300'}`}
                >
                  <Crosshair className="w-3.5 h-3.5" />
                  {placingPoint ? 'Click the map…' : 'Place Pin'}
                </button>
                {tempLat != null && (
                  <span className="text-xs text-slate-600">{tempLat.toFixed(5)}, {tempLng!.toFixed(5)}</span>
                )}
              </div>
            ) : (
              <div className="flex items-center gap-2 flex-wrap">
                <button
                  onClick={() => setDrawingPath((v) => !v)}
                  className={`flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-lg border ${drawingPath ? 'bg-orange-500 text-white border-orange-500' : 'bg-white text-slate-600 border-slate-300'}`}
                >
                  <PenLine className="w-3.5 h-3.5" />
                  {drawingPath ? 'Stop Drawing' : 'Start Drawing'}
                </button>
                <button
                  onClick={() => setTempPath((p) => p.slice(0, -1))}
                  disabled={tempPath.length === 0}
                  className="flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-lg border border-slate-300 bg-white text-slate-600 disabled:opacity-40"
                >
                  <Undo2 className="w-3.5 h-3.5" />
                  Undo Last Point
                </button>
                <span className="text-xs text-slate-500">{tempPath.length} point(s) — needs at least 2</span>
              </div>
            )}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="sm:col-span-2">
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Asset Name</label>
              <input value={draft.assetName} onChange={(e) => setDraft((d) => ({ ...d, assetName: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Village</label>
              <select value={draft.villageId} onChange={(e) => setDraft((d) => ({ ...d, villageId: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option value="">Select village…</option>
                {villages.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Ward No.</label>
              <input type="number" value={draft.wardNo} onChange={(e) => setDraft((d) => ({ ...d, wardNo: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Status</label>
              <select value={draft.status} onChange={(e) => setDraft((d) => ({ ...d, status: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option>Working</option><option>Not Working</option><option>Under Construction</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Condition</label>
              <select value={draft.condition} onChange={(e) => setDraft((d) => ({ ...d, condition: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option>Good</option><option>Fair</option><option>Poor</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Installed Date</label>
              <input type="date" value={draft.installedDate} onChange={(e) => setDraft((d) => ({ ...d, installedDate: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Last Inspected</label>
              <input type="date" value={draft.lastInspected} onChange={(e) => setDraft((d) => ({ ...d, lastInspected: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Photo</label>
              <input type="file" accept="image/*" onChange={(e) => setPhotoFile(e.target.files?.[0] ?? null)} className="w-full text-xs" />
            </div>
            <div className="sm:col-span-3">
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Remarks</label>
              <textarea value={draft.remarks} onChange={(e) => setDraft((d) => ({ ...d, remarks: e.target.value }))} rows={2} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
          </div>

          <button
            disabled={!canSaveNew || isSubmitting}
            onClick={saveNew}
            className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg"
          >
            {isSubmitting ? 'Saving…' : 'Save Asset'}
          </button>
        </div>
      )}

      {selected && !isAdding && (
        <div className="bg-white border border-slate-200 rounded-2xl p-5 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="font-bold text-slate-900">{selected.asset_name}</h2>
              <p className="text-xs text-slate-400">{selected.category} / {selected.subtype} · {selected.geometry_type}</p>
            </div>
            <button onClick={() => setSelected(null)} className="text-slate-400 hover:text-slate-600"><X className="w-4 h-4" /></button>
          </div>

          {actionError && <p className="text-xs text-red-600 bg-red-50 border border-red-100 rounded-lg p-2">{actionError}</p>}

          {selected.photo_url && (
            <img src={api.mediaUrl(selected.photo_url)} alt={selected.asset_name} className="w-full max-w-xs rounded-xl border border-slate-200" />
          )}

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="sm:col-span-2">
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Asset Name</label>
              <input value={editFields.assetName ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, assetName: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Village</label>
              <select value={editFields.villageId ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, villageId: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                {villages.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Ward No.</label>
              <input type="number" value={editFields.wardNo ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, wardNo: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Status</label>
              <select value={editFields.status ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, status: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option>Working</option><option>Not Working</option><option>Under Construction</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Condition</label>
              <select value={editFields.condition ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, condition: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option>Good</option><option>Fair</option><option>Poor</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Installed Date</label>
              <input type="date" value={editFields.installedDate ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, installedDate: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Last Inspected</label>
              <input type="date" value={editFields.lastInspected ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, lastInspected: e.target.value }))} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
            <div>
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Replace Photo</label>
              <input type="file" accept="image/*" onChange={(e) => setPhotoFile(e.target.files?.[0] ?? null)} className="w-full text-xs" />
            </div>
            <div className="sm:col-span-3">
              <label className="text-[10px] font-bold text-slate-500 uppercase block mb-1">Remarks</label>
              <textarea value={editFields.remarks ?? ''} onChange={(e) => setEditFields((f) => ({ ...f, remarks: e.target.value }))} rows={2} className="w-full text-xs border border-slate-300 rounded-lg px-2.5 py-1.5" />
            </div>
          </div>

          <p className="text-[11px] text-slate-400">
            Location/path can't be edited here — delete and re-add the asset if the mapped position was wrong.
          </p>

          <div className="flex items-center gap-2">
            <button disabled={isSubmitting} onClick={saveEdit} className="bg-accent hover:bg-accent-dark disabled:opacity-50 text-white text-xs font-bold px-4 py-2 rounded-lg">
              {isSubmitting ? 'Saving…' : 'Save Changes'}
            </button>
            <button disabled={isSubmitting} onClick={deleteAsset} className="flex items-center gap-1.5 text-xs font-bold px-4 py-2 rounded-lg border border-red-300 text-red-600 hover:bg-red-50">
              <Trash2 className="w-3.5 h-3.5" />
              Delete
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
