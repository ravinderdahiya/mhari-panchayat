import { useEffect, useMemo, useRef, useState } from 'react';
import { Chart as ChartJS, ArcElement, Tooltip, Legend, LineElement, PointElement, LinearScale, CategoryScale } from 'chart.js';
import { Doughnut, Line } from 'react-chartjs-2';
import type MapView from '@arcgis/core/views/MapView.js';
import Graphic from '@arcgis/core/Graphic.js';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer.js';
import UniqueValueRenderer from '@arcgis/core/renderers/UniqueValueRenderer.js';
import Extent from '@arcgis/core/geometry/Extent.js';
import ArcGISMap from '../map/ArcGISMap';
import { dotSymbol } from '../map/symbols';
import { createStreetsBasemap, createWorldImageryBasemap } from '../map/basemap';
import { toArcgisPoint, toArcgisXY } from '../map/coords';
import { useLatestRef } from '../map/useLatestRef';
import { ListChecks, Clock, Wrench } from 'lucide-react';
import * as api from '../services/api';
import type { Complaint, ComplaintReports, ComplaintStatus } from '../types';

ChartJS.register(ArcElement, Tooltip, Legend, LineElement, PointElement, LinearScale, CategoryScale);

// Fixed categorical order (never re-cycled per filter) - validated CVD-safe
// sequence from the dataviz palette (blue, green, magenta, yellow, aqua,
// orange, violet, red). Reused verbatim here (same 8 hues, same order) for
// the fixed status vocabulary - the order itself is the CVD-safety
// mechanism, so statuses are mapped onto it rather than re-deriving a new
// "semantic" set that would need re-validating from scratch.
const CATEGORY_COLORS = [
  '#2a78d6', '#008300', '#e87ba4', '#eda100', '#1baf7a', '#eb6834', '#4a3aa7', '#e34948',
];

const ALL_STATUSES = ['Pending', 'Acknowledged', 'Surveyed', 'In_Progress', 'Resolved', 'Rejected', 'Closed', 'Reopened'];
const STATUS_CHART_COLORS: Record<string, string> = Object.fromEntries(ALL_STATUSES.map((s, i) => [s, CATEGORY_COLORS[i]]));

// Map marker legend: 5-color scheme grouping the 8 granular statuses into the
// stages a field team cares about at a glance. Reopened counts as "New" (it's
// back in the queue needing attention) and Surveyed counts as "In Progress"
// (fieldwork has started but isn't done).
const MAP_LEGEND = [
  { label: 'New', color: '#B5482E', statuses: ['Pending', 'Reopened'] },
  { label: 'Accepted', color: '#C68A16', statuses: ['Acknowledged'] },
  { label: 'In Progress', color: '#A86A21', statuses: ['Surveyed', 'In_Progress'] },
  { label: 'Closed', color: '#3F6B4F', statuses: ['Resolved', 'Closed'] },
  { label: 'Rejected', color: '#3C5E7D', statuses: ['Rejected'] },
] as const;

interface DashboardPageProps {
  onNavigateToComplaints: (status: ComplaintStatus | 'All') => void;
  onNavigateToComplaint: (id: number) => void;
}

export default function DashboardPage({ onNavigateToComplaints, onNavigateToComplaint }: DashboardPageProps) {
  const [reports, setReports] = useState<ComplaintReports | null>(null);
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [error, setError] = useState('');
  const [excludedGroups, setExcludedGroups] = useState<Set<string>>(new Set());
  const [excludedCategories, setExcludedCategories] = useState<Set<string>>(new Set());

  useEffect(() => {
    api.getComplaintReports()
      .then(({ reports }) => setReports(reports))
      .catch((err) => setError((err as Error).message));
    api.getComplaints()
      .then(({ complaints }) => setComplaints(complaints))
      .catch(() => {});
  }, []);

  const heroStats = reports ? [
    { label: 'Total Complaints', value: reports.total, icon: ListChecks, filter: 'All' as const },
    { label: 'Pending', value: reports.pending, icon: Clock, filter: 'Pending' as const },
    { label: 'In Progress', value: reports.inProgress, icon: Wrench, filter: 'In_Progress' as const },
  ] : [];

  const categoryEntries = reports ? Object.entries(reports.byCategory) : [];
  const categoryTotal = categoryEntries.reduce((sum, [, count]) => sum + count, 0);

  const statusEntries = reports ? ALL_STATUSES.map((s) => [s, reports.byStatus[s] ?? 0] as const) : [];
  const statusTotal = statusEntries.reduce((sum, [, count]) => sum + count, 0);

  const mapPoints = complaints.filter((c) => c.lat !== null && c.long !== null);
  const mapCategories = useMemo(
    () => Array.from(new Set(mapPoints.map((c) => c.category.name))).sort(),
    [mapPoints],
  );
  const groupOf = (status: string) => MAP_LEGEND.find((g) => (g.statuses as readonly string[]).includes(status))?.label ?? 'Other';
  const filteredMapPoints = mapPoints.filter(
    (c) => !excludedGroups.has(groupOf(c.status)) && !excludedCategories.has(c.category.name),
  );
  const toggleSetMember = (set: Set<string>, setSet: (s: Set<string>) => void, value: string) => {
    const next = new Set(set);
    if (next.has(value)) next.delete(value); else next.add(value);
    setSet(next);
  };
  const mapCenter: [number, number] = mapPoints.length
    ? [mapPoints[0].lat!, mapPoints[0].long!]
    : [29.0588, 76.0856]; // Haryana, default when nothing has coordinates yet

  const [view, setView] = useState<MapView | null>(null);
  const [mapLayer, setMapLayer] = useState<'imagery' | 'streets'>('imagery');
  const [filterTab, setFilterTab] = useState<'status' | 'category'>('status');
  const pointLayerRef = useRef<FeatureLayer | null>(null);
  const onNavigateToComplaintRef = useLatestRef(onNavigateToComplaint);

  const isInitialBasemapRef = useRef(true);
  useEffect(() => {
    if (!view?.map) return;
    // Skip the run that fires right when `view` first becomes non-null -
    // ArcGISMap already set up the default (imagery) basemap itself, so
    // reassigning it here too would just restart an in-flight tile fetch.
    if (isInitialBasemapRef.current) {
      isInitialBasemapRef.current = false;
      return;
    }
    view.map.basemap = mapLayer === 'streets' ? createStreetsBasemap() : createWorldImageryBasemap();
  }, [view, mapLayer]);

  // Register the popup's "View Details" action handler once per view.
  useEffect(() => {
    if (!view?.popup) return undefined;
    const popup = view.popup;
    const handle = popup.on('trigger-action', (event) => {
      if (event.action.id !== 'view-details') return;
      const id = popup.selectedFeature?.attributes?.id;
      if (id != null) onNavigateToComplaintRef.current(id);
    });
    return () => handle.remove();
  }, [view, onNavigateToComplaintRef]);

  // Rebuild the points FeatureLayer whenever the filtered set changes.
  useEffect(() => {
    if (!view) return;

    const graphics = filteredMapPoints.map((c) => new Graphic({
      geometry: toArcgisPoint(c.lat!, c.long!),
      attributes: {
        id: c.id,
        code: c.code ?? `CMP-${c.id}`,
        legendGroup: groupOf(c.status),
        category: c.category.name,
        statusLabel: c.status.replace('_', ' '),
      },
    }));

    const layer = new FeatureLayer({
      source: graphics,
      objectIdField: 'id',
      geometryType: 'point',
      fields: [
        { name: 'id', type: 'oid' },
        { name: 'code', type: 'string' },
        { name: 'legendGroup', type: 'string' },
        { name: 'category', type: 'string' },
        { name: 'statusLabel', type: 'string' },
      ],
      featureReduction: { type: 'cluster', clusterRadius: '80px' },
      renderer: new UniqueValueRenderer({
        field: 'legendGroup',
        defaultSymbol: dotSymbol('#64748b'),
        uniqueValueInfos: MAP_LEGEND.map(({ label, color }) => ({ value: label, symbol: dotSymbol(color) })),
      }),
      popupTemplate: {
        title: 'Complaint {code}',
        content: '{category} — {statusLabel}',
        actions: [{ type: 'button', title: 'View Details', id: 'view-details' }],
      },
    });

    if (!view.map) return;
    if (pointLayerRef.current) view.map.remove(pointLayerRef.current);
    view.map.add(layer);
    pointLayerRef.current = layer;

    if (filteredMapPoints.length > 0) {
      const xy = filteredMapPoints.map((c) => toArcgisXY(c.lat!, c.long!));
      const xs = xy.map(([x]) => x);
      const ys = xy.map(([, y]) => y);
      const extent = new Extent({
        xmin: Math.min(...xs), xmax: Math.max(...xs),
        ymin: Math.min(...ys), ymax: Math.max(...ys),
        spatialReference: { wkid: 4326 },
      }).expand(1.2);
      void view.goTo({ target: extent }, { duration: 300 })
        .then(() => { if (view.zoom > 13) return view.goTo({ zoom: 13 }); })
        .catch(() => {});
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, filteredMapPoints]);

  const topClosedCount = reports?.closedByPerson[0]?.count ?? 0;
  const closedTotal = reports?.closedByPerson.reduce((sum, p) => sum + p.count, 0) ?? 0;

  return (
    <div className="space-y-6">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}

      {!reports ? (
        <p className="text-sm text-slate-400">Loading…</p>
      ) : (
        <>
          <div className="relative bg-white border border-slate-200 rounded-2xl overflow-hidden h-[36rem]">
            <div className="absolute inset-0">
              <ArcGISMap center={mapCenter} zoom={8} scrollWheelZoom={false} onViewReady={setView} />
            </div>

            <div className="absolute top-4 left-4 z-20 flex flex-col gap-2.5">
              {heroStats.map(({ label, value, icon: Icon, filter }) => (
                <button
                  key={label}
                  onClick={() => onNavigateToComplaints(filter)}
                  className="text-left bg-paper rounded-md shadow-lg px-4 py-2.5 flex items-center gap-2.5 min-w-[190px] cursor-pointer"
                >
                  <Icon className="w-4 h-4 text-accent shrink-0" />
                  <div>
                    <span className="font-serif font-semibold text-[15px] text-ink mr-1 tabular-nums">{value}</span>
                    <span className="text-[12.5px] text-muted">{label}</span>
                  </div>
                </button>
              ))}
            </div>

            <div className="absolute top-4 right-4 z-20 flex flex-col gap-3 w-[230px]">
              <div className="bg-paper rounded-lg shadow-lg p-3">
                <div className="flex gap-2">
                  <button
                    onClick={() => setMapLayer('streets')}
                    className={`flex-1 h-14 rounded-md flex items-end justify-center pb-1.5 text-[10.5px] font-semibold text-white cursor-pointer ${mapLayer === 'streets' ? 'outline outline-2 outline-accent outline-offset-1' : ''}`}
                    style={{ background: 'linear-gradient(135deg,#DDD3B2,#C9BE96)' }}
                  >
                    Map
                  </button>
                  <button
                    onClick={() => setMapLayer('imagery')}
                    className={`flex-1 h-14 rounded-md flex items-end justify-center pb-1.5 text-[10.5px] font-semibold text-white cursor-pointer ${mapLayer === 'imagery' ? 'outline outline-2 outline-accent outline-offset-1' : ''}`}
                    style={{ background: 'linear-gradient(135deg,#5A6E4C,#3F5233)' }}
                  >
                    Satellite
                  </button>
                </div>
              </div>

              <div className="bg-paper rounded-lg shadow-lg p-3.5">
                <div className="flex gap-4 mb-3 border-b border-line pb-2">
                  <button
                    onClick={() => setFilterTab('status')}
                    className={`text-[11px] font-bold tracking-wide cursor-pointer ${filterTab === 'status' ? 'text-ink border-b-2 border-accent pb-2 -mb-2' : 'text-muted'}`}
                  >
                    STATUS
                  </button>
                  <button
                    onClick={() => setFilterTab('category')}
                    className={`text-[11px] font-bold tracking-wide cursor-pointer ${filterTab === 'category' ? 'text-ink border-b-2 border-accent pb-2 -mb-2' : 'text-muted'}`}
                  >
                    CATEGORY
                  </button>
                </div>

                {filterTab === 'status' ? (
                  <div className="space-y-2">
                    {MAP_LEGEND.map(({ label, color }) => (
                      <label key={label} className="flex items-center gap-2 text-[12.5px] cursor-pointer">
                        <input
                          type="checkbox"
                          checked={!excludedGroups.has(label)}
                          onChange={() => toggleSetMember(excludedGroups, setExcludedGroups, label)}
                          className="accent-accent w-3.5 h-3.5"
                        />
                        <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: color }} />
                        {label}
                      </label>
                    ))}
                  </div>
                ) : (
                  <div className="space-y-2 max-h-48 overflow-y-auto">
                    {mapCategories.length === 0 && <p className="text-xs text-muted">No categories yet.</p>}
                    {mapCategories.map((name) => (
                      <label key={name} className="flex items-center gap-2 text-[12.5px] cursor-pointer">
                        <input
                          type="checkbox"
                          checked={!excludedCategories.has(name)}
                          onChange={() => toggleSetMember(excludedCategories, setExcludedCategories, name)}
                          className="accent-accent w-3.5 h-3.5"
                        />
                        {name}
                      </label>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {(mapPoints.length === 0 || filteredMapPoints.length === 0) && (
              <div className="absolute bottom-4 left-4 z-20 bg-paper rounded-md shadow-lg px-3 py-2 text-xs text-muted">
                {mapPoints.length === 0 ? 'No complaints have location data yet.' : 'No complaints match the current filters.'}
              </div>
            )}
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div className="bg-white border border-slate-200 rounded-2xl p-5">
              <h3 className="text-xs font-bold text-slate-500 uppercase mb-4">Complaints by Status</h3>
              <div className="flex flex-col sm:flex-row items-center gap-6">
                <div className="w-48 h-48 shrink-0">
                  <Doughnut
                    data={{
                      labels: statusEntries.map(([s]) => s.replace('_', ' ')),
                      datasets: [{
                        data: statusEntries.map(([, count]) => count),
                        backgroundColor: statusEntries.map(([s]) => STATUS_CHART_COLORS[s]),
                        borderColor: '#fcfcfb',
                        borderWidth: 2,
                      }],
                    }}
                    options={{ plugins: { legend: { display: false } }, cutout: '62%' }}
                  />
                </div>
                <ul className="flex-1 w-full space-y-1.5">
                  {statusEntries.filter(([, count]) => count > 0).map(([status, count]) => (
                    <li key={status} className="flex items-center justify-between text-xs">
                      <span className="flex items-center gap-2">
                        <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: STATUS_CHART_COLORS[status] }} />
                        <span className="text-slate-700 font-semibold">{status.replace('_', ' ')}</span>
                      </span>
                      <span className="text-slate-400 tabular-nums">
                        {count} ({statusTotal ? Math.round((count / statusTotal) * 100) : 0}%)
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            <div className="bg-white border border-slate-200 rounded-2xl p-5">
              <h3 className="text-xs font-bold text-slate-500 uppercase mb-4">Complaints by Category</h3>
              {categoryEntries.length === 0 ? (
                <p className="text-sm text-slate-400">No complaints yet.</p>
              ) : (
                <div className="flex flex-col sm:flex-row items-center gap-6">
                  <div className="w-48 h-48 shrink-0">
                    <Doughnut
                      data={{
                        labels: categoryEntries.map(([name]) => name),
                        datasets: [{
                          data: categoryEntries.map(([, count]) => count),
                          backgroundColor: categoryEntries.map((_, i) => CATEGORY_COLORS[i % CATEGORY_COLORS.length]),
                          borderColor: '#fcfcfb',
                          borderWidth: 2,
                        }],
                      }}
                      options={{ plugins: { legend: { display: false } }, cutout: '62%' }}
                    />
                  </div>
                  <ul className="flex-1 w-full space-y-1.5">
                    {categoryEntries.map(([name, count], i) => (
                      <li key={name} className="flex items-center justify-between text-xs">
                        <span className="flex items-center gap-2">
                          <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: CATEGORY_COLORS[i % CATEGORY_COLORS.length] }} />
                          <span className="text-slate-700 font-semibold">{name}</span>
                        </span>
                        <span className="text-slate-400 tabular-nums">
                          {count} ({categoryTotal ? Math.round((count / categoryTotal) * 100) : 0}%)
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl p-5">
            <h3 className="text-xs font-bold text-slate-500 uppercase mb-4">Complaint Trends (Last 30 Days)</h3>
            <Line
              data={{
                labels: reports.trend.map((t) => new Date(t.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })),
                datasets: (['Pending', 'Acknowledged', 'Resolved', 'Closed'] as const).map((status) => ({
                  label: status,
                  data: reports.trend.map((t) => t[status]),
                  borderColor: STATUS_CHART_COLORS[status],
                  backgroundColor: STATUS_CHART_COLORS[status],
                  tension: 0.3,
                  pointRadius: 2,
                })),
              }}
              options={{
                plugins: { legend: { position: 'top', labels: { boxWidth: 10, font: { size: 11 } } } },
                scales: { y: { beginAtZero: true, ticks: { precision: 0 } } },
              }}
            />
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl p-5">
            <h3 className="text-xs font-bold text-slate-500 uppercase mb-4">Complaints Closed by Person</h3>
            {reports.closedByPerson.length === 0 ? (
              <p className="text-sm text-slate-400">No complaints resolved yet.</p>
            ) : (
              <ul className="space-y-3">
                {reports.closedByPerson.map((p, i) => {
                  const label = p.name || p.username;
                  const initials = label.slice(0, 2).toUpperCase();
                  return (
                    <li key={p.user_id}>
                      <div className="flex items-center gap-2.5">
                        <span className="w-7 h-7 rounded-full bg-accent-soft text-sidebar text-[10px] font-bold flex items-center justify-center shrink-0">
                          {initials}
                        </span>
                        <span className="text-xs font-semibold text-slate-700 flex-1">{label}</span>
                        <span className="text-[10px] font-bold text-slate-400">Top {i + 1}</span>
                        <span className="text-xs text-slate-400 tabular-nums w-28 text-right">
                          {p.count} ({closedTotal ? Math.round((p.count / closedTotal) * 100) : 0}%) · {p.avgHours}h
                        </span>
                      </div>
                      <div className="mt-1.5 h-1.5 bg-slate-100 rounded-full overflow-hidden">
                        <div className="h-full bg-accent rounded-full" style={{ width: `${topClosedCount ? (p.count / topClosedCount) * 100 : 0}%` }} />
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </>
      )}
    </div>
  );
}
