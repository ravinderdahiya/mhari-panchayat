import { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { Chart as ChartJS, ArcElement, Tooltip, Legend, LineElement, PointElement, LinearScale, CategoryScale } from 'chart.js';
import { Doughnut, Line } from 'react-chartjs-2';
import type MapView from '@arcgis/core/views/MapView.js';
import Graphic from '@arcgis/core/Graphic.js';
import FeatureLayer from '@arcgis/core/layers/FeatureLayer.js';
import MapImageLayer from '@arcgis/core/layers/MapImageLayer.js';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer.js';
import Polygon from '@arcgis/core/geometry/Polygon.js';
import UniqueValueRenderer from '@arcgis/core/renderers/UniqueValueRenderer.js';
import Extent from '@arcgis/core/geometry/Extent.js';
import * as reactiveUtils from '@arcgis/core/core/reactiveUtils.js';
import ArcGISMap from '../map/ArcGISMap';
import { dotSymbol, diamondSymbol, highlightFillSymbol } from '../map/symbols';
import { createStreetsBasemap, createWorldImageryBasemap } from '../map/basemap';
import { toArcgisPoint, toArcgisXY } from '../map/coords';
import { useLatestRef } from '../map/useLatestRef';
import { ListChecks, Hourglass, Wrench, Map as MapIcon, Satellite, ClipboardList, Search, X, ChevronLeft, ChevronRight, MapPin, SlidersHorizontal } from 'lucide-react';
import * as api from '../services/api';
import ComplaintPopupCard from '../components/ComplaintPopupCard';
import SurveyPopupCard from '../components/SurveyPopupCard';
import PanchayatPopupCard from '../components/PanchayatPopupCard';
import type { AssetSurvey, Block, Complaint, ComplaintReports, ComplaintStatus, District, Panchayat, Tehsil, Village } from '../types';

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

// Asset-survey marker legend: the 13 review_status values grouped into the
// 4 stages worth telling apart at a glance on the map (see
// AssetSurveysPage.tsx's REVIEW_LABEL for the full per-status breakdown,
// shown in the marker popup instead of here).
const SURVEY_MAP_LEGEND = [
  {
    label: 'In Review', color: '#2a78d6', statuses: [
      'submitted', 'pending', 'gram_sachiv_reviewed', 'gram_sachiv_approved',
      'bdpo_reviewed', 'bdpo_forwarded', 'ddpo_reviewed', 'ddpo_approved',
      'xen_reviewed', 'xen_forwarded',
    ],
  },
  { label: 'Approved', color: '#3F6B4F', statuses: ['approved'] },
  { label: 'Returned', color: '#C68A16', statuses: ['returned'] },
  { label: 'Rejected', color: '#3C5E7D', statuses: ['rejected'] },
] as const;

interface LocationSelection {
  level: 'district' | 'tehsil' | 'block' | 'panchayat' | 'village';
  id: number;
  name: string;
}

const LOCATION_LEVEL_LABEL: Record<LocationSelection['level'], string> = {
  district: 'District', tehsil: 'Tehsil', block: 'Block', panchayat: 'Panchayat', village: 'Village',
};

// Lets the same search box also jump straight to a GPS coordinate, typed as
// "lat, long" (comma and/or whitespace separated) - e.g. pasted from a
// survey's GPS field. Not treated as a LocationSelection (it isn't a
// district/tehsil/block/panchayat/village entity, so it can't filter
// complaints/surveys) - just pans the map there and drops a pin.
function parseLatLong(query: string): { lat: number; lng: number } | null {
  const parts = query.trim().split(/[\s,]+/).filter(Boolean);
  if (parts.length !== 2) return null;
  const lat = Number(parts[0]);
  const lng = Number(parts[1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
}

interface DashboardPageProps {
  onNavigateToComplaints: (status: ComplaintStatus | 'All') => void;
  onNavigateToComplaint: (id: number) => void;
}

export default function DashboardPage({ onNavigateToComplaints, onNavigateToComplaint }: DashboardPageProps) {
  const [reports, setReports] = useState<ComplaintReports | null>(null);
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [surveys, setSurveys] = useState<AssetSurvey[]>([]);
  const [error, setError] = useState('');
  const [excludedGroups, setExcludedGroups] = useState<Set<string>>(new Set());
  const [excludedCategories, setExcludedCategories] = useState<Set<string>>(new Set());
  const [excludedSurveyGroups, setExcludedSurveyGroups] = useState<Set<string>>(new Set());
  const [showComplaintsLayer, setShowComplaintsLayer] = useState(true);
  const [showSurveysLayer, setShowSurveysLayer] = useState(true);
  const [legendOpen, setLegendOpen] = useState(true);

  // District/Tehsil/Block/Village search - narrows both layers to one
  // location and re-fits the map there (see the combined extent-fit effect
  // below, which already reacts to filteredMapPoints/filteredSurveyMapPoints
  // changing for any reason, search included).
  const [selectedLocation, setSelectedLocation] = useState<LocationSelection | null>(null);
  const [locationQuery, setLocationQuery] = useState('');
  const [locationSuggestOpen, setLocationSuggestOpen] = useState(false);
  const [locationMasterLoaded, setLocationMasterLoaded] = useState(false);
  const [districtsMaster, setDistrictsMaster] = useState<District[]>([]);
  const [tehsilsMaster, setTehsilsMaster] = useState<Tehsil[]>([]);
  const [blocksMaster, setBlocksMaster] = useState<Block[]>([]);
  const [villageSuggestions, setVillageSuggestions] = useState<Village[]>([]);
  const [panchayatSuggestions, setPanchayatSuggestions] = useState<Panchayat[]>([]);

  // Districts/tehsils/blocks are small lists (well under a hundred rows) -
  // fine to load once, in full, the first time the search box is used.
  // Panchayats (~6.2k) and villages (~7k) are searched server-side instead,
  // below (see SurveyorsPage's own note on this).
  const loadLocationMaster = () => {
    if (locationMasterLoaded) return;
    setLocationMasterLoaded(true);
    Promise.all([
      api.masterApi('districts').list(),
      api.masterApi('tehsils').list(),
      api.masterApi('blocks').list(),
    ])
      .then(([d, t, b]) => {
        setDistrictsMaster(d.items || []);
        setTehsilsMaster(t.items || []);
        setBlocksMaster(b.items || []);
      })
      .catch(() => {});
  };

  useEffect(() => {
    const q = locationQuery.trim();
    if (q.length < 2) {
      setVillageSuggestions([]);
      setPanchayatSuggestions([]);
      return undefined;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      // `search` is only applied server-side for paginated requests (see
      // MasterDataController::index) - without `paginated: true` this was
      // silently ignoring the query and returning the first 8 rows
      // alphabetically, regardless of what was typed.
      api.masterApi('villages').list({ search: q, paginated: true, perPage: 8, status: 'active' })
        .then((res) => { if (!cancelled) setVillageSuggestions((res.items || []).slice(0, 8)); })
        .catch(() => {});
      api.masterApi('panchayats').list({ search: q, paginated: true, perPage: 8, status: 'active' })
        .then((res) => { if (!cancelled) setPanchayatSuggestions((res.items || []).slice(0, 8)); })
        .catch(() => {});
    }, 300);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [locationQuery]);

  useEffect(() => {
    api.getComplaintReports()
      .then(({ reports }) => setReports(reports))
      .catch((err) => setError((err as Error).message));
    api.getComplaints()
      .then(({ complaints }) => setComplaints(complaints))
      .catch(() => {});
    api.getAssetSurveysForMap()
      .then(({ surveys }) => setSurveys(surveys))
      .catch(() => {});
  }, []);

  const heroStats = reports ? [
    { label: 'Total Complaints', value: reports.total, icon: ListChecks, filter: 'All' as const },
    { label: 'Pending', value: reports.pending, icon: Hourglass, filter: 'Pending' as const },
    { label: 'In Progress', value: reports.inProgress, icon: Wrench, filter: 'In_Progress' as const },
  ] : [];

  const categoryEntries = reports ? Object.entries(reports.byCategory) : [];
  const categoryTotal = categoryEntries.reduce((sum, [, count]) => sum + count, 0);

  const statusEntries = reports ? ALL_STATUSES.map((s) => [s, reports.byStatus[s] ?? 0] as const) : [];
  const statusTotal = statusEntries.reduce((sum, [, count]) => sum + count, 0);

  const mapPoints = useMemo(() => complaints.filter((c) => c.lat !== null && c.long !== null), [complaints]);
  const mapCategories = useMemo(
    () => Array.from(new Set(mapPoints.map((c) => c.category?.name ?? 'Uncategorised'))).sort(),
    [mapPoints],
  );
  const groupOf = (status: string) => MAP_LEGEND.find((g) => (g.statuses as readonly string[]).includes(status))?.label ?? 'Other';
  const normName = (value: string | null | undefined) => (value ?? '').trim().toLowerCase();
  // Complaints/surveys can be submitted without every location field
  // resolved to a master-data ID (free-text-only entries, or a surveyor
  // with no fixed panchayat/block) - matching by ID alone silently dropped
  // those from search results. Falling back to a name match against
  // whichever free-text field the entity actually has picks them back up.
  // Block has no free-text fallback on either entity (only the resolved
  // ID), and tehsil has no equivalent on AssetSurvey at all - both stay
  // ID-only / unmatched rather than guessing.
  const complaintMatchesLocation = (c: Complaint): boolean => {
    if (!selectedLocation) return true;
    const name = normName(selectedLocation.name);
    switch (selectedLocation.level) {
      case 'district': return c.district_id === selectedLocation.id || normName(c.district?.name) === name;
      case 'tehsil': return c.tehsil_id === selectedLocation.id || normName(c.tehsil?.name) === name;
      case 'block': return c.panchayatMaster?.block_id === selectedLocation.id;
      case 'panchayat': return c.panchayat_id === selectedLocation.id || normName(c.panchayat) === name;
      case 'village': return c.village_id === selectedLocation.id || normName(c.village) === name;
    }
  };
  const surveyMatchesLocation = (s: AssetSurvey): boolean => {
    if (!selectedLocation) return true;
    const name = normName(selectedLocation.name);
    switch (selectedLocation.level) {
      case 'district': return s.districtId === selectedLocation.id || normName(s.district) === name;
      case 'tehsil': return false;
      case 'block': return s.blockId === selectedLocation.id;
      case 'panchayat': return s.panchayatId === selectedLocation.id || normName(s.panchayat) === name;
      case 'village': return normName(s.village) === name;
    }
  };

  // Memoized so this only produces a new array (and re-triggers the map
  // effects below, including the extent-fit one) when something that
  // actually changes the result changes - not on every unrelated re-render
  // (e.g. typing in the location search box before selecting anything),
  // which was re-firing the extent-fit effect and re-issuing view.goTo()
  // mid-animation, unpredictably interrupting its own zoom.
  const filteredMapPoints = useMemo(
    () => showComplaintsLayer ? mapPoints.filter(
      (c) => !excludedGroups.has(groupOf(c.status)) && !excludedCategories.has(c.category?.name ?? 'Uncategorised') && complaintMatchesLocation(c),
    ) : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [mapPoints, showComplaintsLayer, excludedGroups, excludedCategories, selectedLocation],
  );

  const surveyMapPoints = useMemo(() => surveys.filter((s) => s.latitude !== null && s.longitude !== null), [surveys]);
  const surveyGroupOf = (status: string) =>
    SURVEY_MAP_LEGEND.find((g) => (g.statuses as readonly string[]).includes(status))?.label ?? 'Other';
  const filteredSurveyMapPoints = useMemo(
    () => showSurveysLayer
      ? surveyMapPoints.filter((s) => !excludedSurveyGroups.has(surveyGroupOf(s.reviewStatus)) && surveyMatchesLocation(s))
      : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [surveyMapPoints, showSurveysLayer, excludedSurveyGroups, selectedLocation],
  );

  const toggleSetMember = (set: Set<string>, setSet: (s: Set<string>) => void, value: string) => {
    const next = new Set(set);
    if (next.has(value)) next.delete(value); else next.add(value);
    setSet(next);
  };
  const mapCenter: [number, number] = mapPoints.length
    ? [mapPoints[0].lat!, mapPoints[0].long!]
    : surveyMapPoints.length
      ? [surveyMapPoints[0].latitude!, surveyMapPoints[0].longitude!]
      : [29.0588, 76.0856]; // Haryana, default when nothing has coordinates yet

  const [view, setView] = useState<MapView | null>(null);
  const [mapLayer, setMapLayer] = useState<'imagery' | 'streets'>('imagery');
  const [filterTab, setFilterTab] = useState<'status' | 'category'>('status');
  const pointLayerRef = useRef<FeatureLayer | null>(null);
  const surveyLayerRef = useRef<FeatureLayer | null>(null);
  const highlightLayerRef = useRef<GraphicsLayer | null>(null);
  const coordPinLayerRef = useRef<GraphicsLayer | null>(null);
  const onNavigateToComplaintRef = useLatestRef(onNavigateToComplaint);
  const complaintsRef = useLatestRef(complaints);
  const surveysRef = useLatestRef(surveys);
  // One entry per content() call, not just the latest - a single click can
  // hit more than one layer at (almost) the same point (e.g. a complaint and
  // a survey marker on top of each other), and the popup widget's combined
  // multi-feature view ("1 of 2") can invoke more than one layer's content()
  // callback for the same click. Eagerly unmounting "whichever was there
  // before" (the previous design) raced across those calls and left
  // whichever feature rendered first blank once the second one unmounted
  // its shared root. Every root here lives until the whole popup closes.
  const popupRootsRef = useRef<Set<{ root: Root; container: HTMLDivElement }>>(new Set());
  // Deferred a tick: unmounting synchronously here can collide with React's
  // own in-progress render of this component (e.g. a click that both
  // selects a new feature and triggers a parent re-render), which React
  // warns about ("Attempted to synchronously unmount a root while React was
  // already rendering"). A fresh task sidesteps whatever call stack
  // triggered this.
  const unmountAllPopupRoots = () => {
    if (popupRootsRef.current.size === 0) return;
    const entries = Array.from(popupRootsRef.current);
    popupRootsRef.current.clear();
    setTimeout(() => entries.forEach(({ root }) => root.unmount()), 0);
  };

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

  // Panchayat/district boundary layer from HARSAC's GIS portal - added once
  // per view, at the bottom of the stack, so it sits under the complaint
  // points layer (which re-adds itself on top on every filter change).
  //
  // NOTE: HARSAC also publishes this same boundary data as a hosted vector
  // tile service (api.gisPanchayatVectorTileUrl) with sharper rendering, but
  // that service's tiling grid is UTM Zone 43N (wkid 32643), not Web Mercator
  // — the ArcGIS JS API can't reproject vector tiles on the fly (unlike this
  // raster MapImageLayer), so it can't be overlaid on this Web Mercator
  // satellite/streets basemap. Forcing the whole view into 32643 to match it
  // was tried and reverted: it broke the geometry engine's WASM module load
  // under this project's Vite base-path setup. Switch back to the vector
  // layer only if HARSAC republishes it in Web Mercator.
  // This service only has 2 layers - dist_bn (district boundary, id 0) and
  // panchayat_bnd (panchayat boundary, id 1) - both wanted, so no sublayers
  // filter needed. Each already has its own minScale set server-side, so
  // they fade in/out correctly as you zoom without client-side scale logic.
  const boundaryLayerRef = useRef<MapImageLayer | null>(null);
  useEffect(() => {
    if (!view?.map) return undefined;
    const layer = new MapImageLayer({
      url: api.gisPanchayatMapServerUrl,
      sublayers: [
        { id: 0, popupEnabled: false }, // dist_bn - no officer data, would just add a redundant tab
        {
          id: 1, // panchayat_bnd (GP_append_1) - carries CPLO/BDPO/DDPO contact fields directly
          popupTemplate: {
            title: '{localbodyname}',
            content: (event) => {
              const container = document.createElement('div');
              const root = createRoot(container);
              const entry = { root, container };
              popupRootsRef.current.add(entry);
              const attributes = event.graphic.attributes;
              root.render(<PanchayatPopupCard attributes={attributes} />);

              // GIS cplo_name is blank for a lot of panchayats, and the
              // layer has no Gram Sachiv fields at all - backfill both from
              // our own users table, keyed by the LGD code both sides share.
              const code = attributes.local_body_code;
              if (code) {
                void api.getPanchayatOfficials(String(code))
                  .then((result) => {
                    if (!popupRootsRef.current.has(entry)) return; // popup moved on
                    root.render(<PanchayatPopupCard attributes={attributes} localOfficials={{ cplo: result.cplo, gram_sachiv: result.gram_sachiv }} />);
                  })
                  .catch(() => {
                    if (!popupRootsRef.current.has(entry)) return;
                    root.render(<PanchayatPopupCard attributes={attributes} localOfficials={null} />);
                  });
              }
              return container;
            },
          },
        },
      ],
    });
    view.map.add(layer, 0);
    boundaryLayerRef.current = layer;
    return () => {
      if (view.map) view.map.remove(layer);
      boundaryLayerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view]);

  // The boundary layer above renders every panchayat in the same thin
  // orange line, so a search result doesn't visually stand out among its
  // neighbours - this draws just the searched District/Tehsil/Block/Village's
  // real boundary polygon(s) on top, in a distinct highlight colour.
  useEffect(() => {
    if (!view?.map) return undefined;
    const layer = new GraphicsLayer();
    view.map.add(layer);
    highlightLayerRef.current = layer;
    return () => {
      if (view.map) view.map.remove(layer);
      highlightLayerRef.current = null;
    };
  }, [view]);

  // Holds the single pin dropped by a "lat, long" search - separate from
  // highlightLayerRef so a coordinate search and a district/block/village
  // search never clear each other out.
  useEffect(() => {
    if (!view?.map) return undefined;
    const layer = new GraphicsLayer();
    view.map.add(layer);
    coordPinLayerRef.current = layer;
    return () => {
      if (view.map) view.map.remove(layer);
      coordPinLayerRef.current = null;
    };
  }, [view]);

  const goToCoordinates = (lat: number, lng: number) => {
    coordPinLayerRef.current?.removeAll();
    coordPinLayerRef.current?.add(new Graphic({ geometry: toArcgisPoint(lat, lng), symbol: dotSymbol('#ef4444') }));
    void view?.goTo({ target: toArcgisPoint(lat, lng), zoom: 16 }, { duration: 300 }).catch(() => {});
    setLocationQuery(`${lat}, ${lng}`);
    setLocationSuggestOpen(false);
  };

  useEffect(() => {
    const layer = highlightLayerRef.current;
    if (!layer) return undefined;
    layer.removeAll();
    if (!selectedLocation) return undefined;

    let cancelled = false;
    api.getLocationExtent(selectedLocation.level, selectedLocation.id)
      .then(async (res) => {
        if (cancelled || !res.codes?.length) return;
        const where = `local_body_code IN (${res.codes.map((code) => `'${code.replace(/'/g, "''")}'`).join(',')})`;
        const url = `${api.gisPanchayatMapServerUrl}/1/query?f=json&outSR=4326&returnGeometry=true&outFields=local_body_code&where=${encodeURIComponent(where)}`;
        const response = await fetch(url);
        const body: { features?: { geometry?: { rings?: number[][][] } }[] } = await response.json();
        if (cancelled) return;
        const graphics = (body.features ?? [])
          .filter((feature): feature is { geometry: { rings: number[][][] } } => Boolean(feature.geometry?.rings))
          .map((feature) => new Graphic({
            geometry: new Polygon({ rings: feature.geometry.rings, spatialReference: { wkid: 4326 } }),
            symbol: highlightFillSymbol(),
          }));
        layer.addMany(graphics);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [view, selectedLocation]);

  // Register the popup's "View Details" action handler once per view, and
  // unmount the React root backing the popup's custom content whenever it
  // closes - the popup widget just detaches the content node, it never
  // unmounts what was rendered into it.
  useEffect(() => {
    if (!view?.popup) return undefined;
    const popup = view.popup;
    const actionHandle = popup.on('trigger-action', (event) => {
      if (event.action.id !== 'view-details') return;
      const id = popup.selectedFeature?.attributes?.id;
      if (id != null) onNavigateToComplaintRef.current(id);
    });
    const visibleHandle = reactiveUtils.watch(() => popup.visible, (visible) => { if (!visible) unmountAllPopupRoots(); });
    return () => {
      actionHandle.remove();
      visibleHandle.remove();
      unmountAllPopupRoots();
    };
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
        category: c.category?.name ?? 'Uncategorised',
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
      renderer: new UniqueValueRenderer({
        field: 'legendGroup',
        defaultSymbol: dotSymbol('#64748b'),
        uniqueValueInfos: MAP_LEGEND.map(({ label, color }) => ({ value: label, symbol: dotSymbol(color) })),
      }),
      popupTemplate: {
        title: 'Complaint {code}',
        content: (event) => {
          const complaint = complaintsRef.current.find((c) => c.id === event.graphic.attributes.id);
          const container = document.createElement('div');
          const root = createRoot(container);
          popupRootsRef.current.add({ root, container });
          root.render(complaint ? <ComplaintPopupCard complaint={complaint} /> : <span className="text-xs text-muted">Complaint details unavailable.</span>);
          return container;
        },
        actions: [{ type: 'button', title: 'View Details', id: 'view-details' }],
      },
    });

    if (!view.map) return;
    if (pointLayerRef.current) view.map.remove(pointLayerRef.current);
    view.map.add(layer);
    pointLayerRef.current = layer;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, filteredMapPoints]);

  // Rebuild the asset-survey points FeatureLayer whenever the filtered set
  // changes - a second, independent layer sharing this same map, distinct
  // from complaints by marker shape (diamond vs circle) as well as color.
  useEffect(() => {
    if (!view) return;

    const graphics = filteredSurveyMapPoints.map((s) => new Graphic({
      geometry: toArcgisPoint(s.latitude!, s.longitude!),
      attributes: {
        id: s.id,
        code: s.assetId,
        legendGroup: surveyGroupOf(s.reviewStatus),
        assetName: s.assetName,
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
        { name: 'assetName', type: 'string' },
      ],
      renderer: new UniqueValueRenderer({
        field: 'legendGroup',
        defaultSymbol: diamondSymbol('#64748b'),
        uniqueValueInfos: SURVEY_MAP_LEGEND.map(({ label, color }) => ({ value: label, symbol: diamondSymbol(color) })),
      }),
      popupTemplate: {
        title: 'Survey {code}',
        content: (event) => {
          const survey = surveysRef.current.find((s) => s.id === event.graphic.attributes.id);
          const container = document.createElement('div');
          const root = createRoot(container);
          popupRootsRef.current.add({ root, container });
          root.render(survey ? <SurveyPopupCard survey={survey} /> : <span className="text-xs text-muted">Survey details unavailable.</span>);
          return container;
        },
      },
    });

    if (!view.map) return;
    if (surveyLayerRef.current) view.map.remove(surveyLayerRef.current);
    view.map.add(layer);
    surveyLayerRef.current = layer;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, filteredSurveyMapPoints]);

  // Fits the view to whatever's actually visible across both layers
  // combined - runs after both layer-rebuild effects above rather than
  // inside either of them, so toggling one layer off doesn't fight the
  // other's own fit-to-extent animation.
  useEffect(() => {
    if (!view) return;

    const goToBox = (xmin: number, xmax: number, ymin: number, ymax: number) => {
      // A single matching point (or a location with a degenerately small
      // boundary) makes a zero-width/zero-height extent - expand(1.2)
      // leaves that at zero too (1.2x nothing is still nothing), so goTo
      // has no visible effect. Pad it manually first so there's always
      // something to expand and zoom to. WGS84 degrees (see toArcgisXY),
      // not meters - 0.01deg is roughly a 1km pad at Haryana's latitude.
      if (xmax - xmin < 0.001) { xmin -= 0.01; xmax += 0.01; }
      if (ymax - ymin < 0.001) { ymin -= 0.01; ymax += 0.01; }
      const extent = new Extent({ xmin, xmax, ymin, ymax, spatialReference: { wkid: 4326 } }).expand(1.2);
      void view.goTo({ target: extent }, { duration: 300 })
        .then(() => { if (view.zoom > 13) return view.goTo({ zoom: 13 }); })
        .catch(() => {});
    };

    const complaintXY = filteredMapPoints.map((c) => toArcgisXY(c.lat!, c.long!));
    const surveyXY = filteredSurveyMapPoints.map((s) => toArcgisXY(s.latitude!, s.longitude!));
    const xy = [...complaintXY, ...surveyXY];

    if (xy.length > 0) {
      const xs = xy.map(([x]) => x);
      const ys = xy.map(([, y]) => y);
      goToBox(Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys));
      return;
    }

    // No complaints/surveys matched (a real possibility for a location that
    // just hasn't had anything reported yet) - fall back to the searched
    // location's own real boundary extent, so the search still navigates
    // there instead of silently doing nothing.
    if (!selectedLocation) return;
    let cancelled = false;
    api.getLocationExtent(selectedLocation.level, selectedLocation.id)
      .then((res) => {
        if (cancelled || !res.extent) return;
        goToBox(res.extent.xmin, res.extent.xmax, res.extent.ymin, res.extent.ymax);
      })
      .catch(() => {});
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view, filteredMapPoints, filteredSurveyMapPoints, selectedLocation]);

  const topClosedCount = reports?.closedByPerson[0]?.count ?? 0;
  const closedTotal = reports?.closedByPerson.reduce((sum, p) => sum + p.count, 0) ?? 0;

  return (
    <div className="space-y-6">
      {error && <p className="text-xs text-status-new bg-status-new/10 border border-status-new/20 rounded-lg p-2">{error}</p>}

      {!reports ? (
        <p className="text-sm text-slate-400">Loading…</p>
      ) : (
        <>
          <div className="relative bg-white border border-slate-200 rounded-2xl overflow-hidden h-[48rem]">
            <div className="absolute inset-0">
              <ArcGISMap center={mapCenter} zoom={8} onViewReady={setView} />
            </div>

            <div
              className="absolute top-4 left-4 z-30 flex items-center gap-2"
              style={{ right: legendOpen ? 282 : 52 }}
            >
              {heroStats.map(({ label, value, icon: Icon, filter }) => (
                <button
                  key={label}
                  onClick={() => onNavigateToComplaints(filter)}
                  className="text-left bg-white/78 backdrop-blur-md border border-white/70 rounded-2xl shadow-md px-3 py-2 flex items-center gap-2 shrink-0 cursor-pointer hover:bg-white/90 transition-colors"
                >
                  <div className="w-9 h-9 rounded-full bg-white/70 flex items-center justify-center shrink-0">
                    <Icon className="w-4 h-4 text-accent" />
                  </div>
                  <div className="w-px h-6 bg-ink/15 shrink-0" />
                  <div className="flex items-baseline gap-1.5">
                    <span className="font-serif font-bold text-[22px] leading-none text-ink tabular-nums underline decoration-2 underline-offset-4 decoration-ink/60">{value}</span>
                    <span className="text-[11.5px] text-ink/60 font-medium whitespace-nowrap">{label}</span>
                  </div>
                </button>
              ))}
              <div className="bg-white/78 backdrop-blur-md border border-white/70 rounded-2xl shadow-md px-3 py-2 flex items-center gap-2 shrink-0">
                <div className="w-9 h-9 rounded-full bg-white/70 flex items-center justify-center shrink-0">
                  <ClipboardList className="w-4 h-4 text-accent" />
                </div>
                <div className="w-px h-6 bg-ink/15 shrink-0" />
                <div className="flex items-baseline gap-1.5">
                  <span className="font-serif font-bold text-[22px] leading-none text-ink tabular-nums underline decoration-2 underline-offset-4 decoration-ink/60">{surveys.length}</span>
                  <span className="text-[11.5px] text-ink/60 font-medium whitespace-nowrap">Asset Surveys</span>
                </div>
              </div>

              <div className="flex-1 min-w-0 max-w-[420px] relative">
                <div className="relative">
                  <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-muted pointer-events-none" />
                  <input
                    value={locationQuery}
                    onFocus={() => { loadLocationMaster(); setLocationSuggestOpen(true); }}
                    onChange={(event) => {
                      setLocationQuery(event.target.value);
                      setLocationSuggestOpen(true);
                      if (selectedLocation) setSelectedLocation(null);
                    }}
                    placeholder="Search district, tehsil, block, panchayat, village or lat, long…"
                    className="w-full pl-11 pr-16 py-[18px] text-xs bg-white/78 backdrop-blur-md rounded-full shadow-md border border-white/70 outline-none focus:ring-2 focus:ring-accent/40"
                  />
                  {(locationQuery || selectedLocation) && (
                    <button
                      onClick={() => {
                        setSelectedLocation(null); setLocationQuery(''); setLocationSuggestOpen(false);
                        coordPinLayerRef.current?.removeAll();
                      }}
                      className="absolute right-10 top-1/2 -translate-y-1/2 text-muted hover:text-ink cursor-pointer"
                      aria-label="Clear location search"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  )}
                  <SlidersHorizontal className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-muted pointer-events-none" />
                </div>

                {locationSuggestOpen && locationQuery.trim().length >= 1 && !selectedLocation && (() => {
                  const q = locationQuery.trim().toLowerCase();
                  const districtMatches = districtsMaster.filter((d) => d.name.toLowerCase().includes(q)).slice(0, 5);
                  const tehsilMatches = tehsilsMaster.filter((t) => t.name.toLowerCase().includes(q)).slice(0, 5);
                  const blockMatches = blocksMaster.filter((b) => b.name.toLowerCase().includes(q)).slice(0, 5);
                  const villageMatches = villageSuggestions;
                  const panchayatMatches = panchayatSuggestions;
                  const groups: Array<[LocationSelection['level'], { id: number; name: string }[]]> = [
                    ['district', districtMatches], ['tehsil', tehsilMatches],
                    ['block', blockMatches], ['panchayat', panchayatMatches], ['village', villageMatches],
                  ];
                  const hasAny = groups.some(([, items]) => items.length > 0);
                  const coords = parseLatLong(locationQuery);

                  return (
                    <div className="mt-1.5 bg-paper rounded-xl shadow-xl border border-line/70 overflow-y-auto max-h-72">
                      {coords && (
                        <div className="py-1 border-b border-line/50">
                          <div className="text-[10px] font-bold tracking-wide text-muted px-3 pt-1.5 pb-1">COORDINATES</div>
                          <button
                            onClick={() => goToCoordinates(coords.lat, coords.lng)}
                            className="w-full text-left px-3 py-1.5 text-xs text-ink hover:bg-cream cursor-pointer flex items-center gap-1.5"
                          >
                            <MapPin className="w-3 h-3 text-accent shrink-0" /> Go to {coords.lat}, {coords.lng}
                          </button>
                        </div>
                      )}
                      {!hasAny && !coords ? (
                        <p className="text-xs text-muted p-3">No matches.</p>
                      ) : groups.map(([level, items]) => items.length === 0 ? null : (
                        <div key={level} className="py-1">
                          <div className="text-[10px] font-bold tracking-wide text-muted px-3 pt-1.5 pb-1">
                            {LOCATION_LEVEL_LABEL[level].toUpperCase()}
                          </div>
                          {items.map((item) => (
                            <button
                              key={item.id}
                              onClick={() => {
                                setSelectedLocation({ level, id: item.id, name: item.name });
                                setLocationQuery(item.name);
                                setLocationSuggestOpen(false);
                              }}
                              className="w-full text-left px-3 py-1.5 text-xs text-ink hover:bg-cream cursor-pointer"
                            >
                              {item.name}
                            </button>
                          ))}
                        </div>
                      ))}
                    </div>
                  );
                })()}

                {selectedLocation && (
                  <div className="mt-1.5 inline-flex items-center gap-1.5 bg-accent-soft text-accent-dark text-[11px] font-semibold px-2.5 py-1.5 rounded-full shadow">
                    {LOCATION_LEVEL_LABEL[selectedLocation.level]}: {selectedLocation.name}
                    <button
                      onClick={() => { setSelectedLocation(null); setLocationQuery(''); }}
                      className="cursor-pointer hover:opacity-70"
                      aria-label="Clear location filter"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </div>
                )}
              </div>
            </div>

            <div className="absolute top-4 right-4 z-20 flex items-start">
              <button
                onClick={() => setLegendOpen((v) => !v)}
                className="mt-1 shrink-0 bg-paper/95 backdrop-blur-sm rounded-l-xl shadow-xl border border-line/70 border-r-0 w-6 h-10 flex items-center justify-center cursor-pointer hover:bg-cream/70 transition-colors"
                aria-label={legendOpen ? 'Hide map legend' : 'Show map legend'}
                title={legendOpen ? 'Hide legend' : 'Show legend'}
              >
                {legendOpen ? <ChevronRight className="w-4 h-4 text-muted" /> : <ChevronLeft className="w-4 h-4 text-muted" />}
              </button>

              <div className={`shrink-0 overflow-hidden transition-[width] duration-300 ease-in-out ${legendOpen ? 'w-[230px]' : 'w-0'}`}>
                <div className="w-[230px] bg-paper/95 backdrop-blur-sm rounded-2xl rounded-tl-none shadow-xl border border-line/70 overflow-hidden">
                  <div className="p-3">
                <div className="flex gap-1 bg-cream rounded-full p-1">
                  <button
                    onClick={() => setMapLayer('streets')}
                    className={`flex-1 flex items-center justify-center gap-1.5 h-8 rounded-full text-[11px] font-semibold cursor-pointer transition-colors ${mapLayer === 'streets' ? 'text-white shadow-sm' : 'text-muted hover:text-ink'}`}
                    style={mapLayer === 'streets' ? { background: 'linear-gradient(135deg,#C9BE96,#A8976A)' } : undefined}
                  >
                    <MapIcon className="w-3.5 h-3.5" />
                    Map
                  </button>
                  <button
                    onClick={() => setMapLayer('imagery')}
                    className={`flex-1 flex items-center justify-center gap-1.5 h-8 rounded-full text-[11px] font-semibold cursor-pointer transition-colors ${mapLayer === 'imagery' ? 'text-white shadow-sm' : 'text-muted hover:text-ink'}`}
                    style={mapLayer === 'imagery' ? { background: 'linear-gradient(135deg,#5A6E4C,#3F5233)' } : undefined}
                  >
                    <Satellite className="w-3.5 h-3.5" />
                    Satellite
                  </button>
                </div>
              </div>

              <div className="border-t border-line" />

              <div className="p-3.5 pb-2.5 space-y-1">
                <label className="flex items-center gap-2 text-[12px] font-semibold cursor-pointer rounded-lg px-1.5 py-1 -mx-1.5 hover:bg-cream/70 transition-colors">
                  <input
                    type="checkbox"
                    checked={showComplaintsLayer}
                    onChange={() => setShowComplaintsLayer((v) => !v)}
                    className="accent-accent w-3.5 h-3.5"
                  />
                  <span className="w-2.5 h-2.5 rounded-full shrink-0 bg-slate-400" />
                  <span className="text-ink/85">Complaints</span>
                </label>
                <label className="flex items-center gap-2 text-[12px] font-semibold cursor-pointer rounded-lg px-1.5 py-1 -mx-1.5 hover:bg-cream/70 transition-colors">
                  <input
                    type="checkbox"
                    checked={showSurveysLayer}
                    onChange={() => setShowSurveysLayer((v) => !v)}
                    className="accent-accent w-3.5 h-3.5"
                  />
                  <span className="w-2.5 h-2.5 rotate-45 shrink-0 bg-slate-400" />
                  <span className="text-ink/85">Asset Surveys</span>
                </label>
              </div>

              {showComplaintsLayer && (
                <>
                  <div className="border-t border-line" />
                  <div className="p-3.5 pt-3">
                    <div className="flex gap-1 bg-cream rounded-full p-1 mb-3">
                      <button
                        onClick={() => setFilterTab('status')}
                        className={`flex-1 h-7 rounded-full text-[10.5px] font-bold tracking-wide cursor-pointer transition-colors ${filterTab === 'status' ? 'bg-white text-ink shadow-sm' : 'text-muted hover:text-ink'}`}
                      >
                        STATUS
                      </button>
                      <button
                        onClick={() => setFilterTab('category')}
                        className={`flex-1 h-7 rounded-full text-[10.5px] font-bold tracking-wide cursor-pointer transition-colors ${filterTab === 'category' ? 'bg-white text-ink shadow-sm' : 'text-muted hover:text-ink'}`}
                      >
                        CATEGORY
                      </button>
                    </div>

                    {filterTab === 'status' ? (
                      <div className="space-y-0.5">
                        {MAP_LEGEND.map(({ label, color }) => (
                          <label key={label} className="flex items-center gap-2 text-[12.5px] cursor-pointer rounded-lg px-1.5 py-1.5 -mx-1.5 hover:bg-cream/70 transition-colors">
                            <input
                              type="checkbox"
                              checked={!excludedGroups.has(label)}
                              onChange={() => toggleSetMember(excludedGroups, setExcludedGroups, label)}
                              className="accent-accent w-3.5 h-3.5"
                            />
                            <span className="w-2.5 h-2.5 rounded-full shrink-0 ring-2 ring-white shadow-sm" style={{ backgroundColor: color }} />
                            <span className="text-ink/85">{label}</span>
                          </label>
                        ))}
                      </div>
                    ) : (
                      <div className="space-y-0.5 max-h-48 overflow-y-auto">
                        {mapCategories.length === 0 && <p className="text-xs text-muted">No categories yet.</p>}
                        {mapCategories.map((name) => (
                          <label key={name} className="flex items-center gap-2 text-[12.5px] cursor-pointer rounded-lg px-1.5 py-1.5 -mx-1.5 hover:bg-cream/70 transition-colors">
                            <input
                              type="checkbox"
                              checked={!excludedCategories.has(name)}
                              onChange={() => toggleSetMember(excludedCategories, setExcludedCategories, name)}
                              className="accent-accent w-3.5 h-3.5"
                            />
                            <span className="text-ink/85">{name}</span>
                          </label>
                        ))}
                      </div>
                    )}
                  </div>
                </>
              )}

              {showSurveysLayer && (
                <>
                  <div className="border-t border-line" />
                  <div className="p-3.5 pt-3">
                    <div className="text-[10.5px] font-bold tracking-wide text-muted mb-2">SURVEY STATUS</div>
                    <div className="space-y-0.5">
                      {SURVEY_MAP_LEGEND.map(({ label, color }) => (
                        <label key={label} className="flex items-center gap-2 text-[12.5px] cursor-pointer rounded-lg px-1.5 py-1.5 -mx-1.5 hover:bg-cream/70 transition-colors">
                          <input
                            type="checkbox"
                            checked={!excludedSurveyGroups.has(label)}
                            onChange={() => toggleSetMember(excludedSurveyGroups, setExcludedSurveyGroups, label)}
                            className="accent-accent w-3.5 h-3.5"
                          />
                          <span className="w-2.5 h-2.5 rotate-45 shrink-0 ring-2 ring-white shadow-sm" style={{ backgroundColor: color }} />
                          <span className="text-ink/85">{label}</span>
                        </label>
                      ))}
                    </div>
                  </div>
                </>
              )}
            </div>
              </div>
            </div>

            {filteredMapPoints.length === 0 && filteredSurveyMapPoints.length === 0 && (
              <div className="absolute bottom-4 left-4 z-20 bg-paper rounded-md shadow-lg px-3 py-2 text-xs text-muted">
                {!showComplaintsLayer && !showSurveysLayer
                  ? 'Both layers are hidden.'
                  : mapPoints.length === 0 && surveyMapPoints.length === 0
                    ? 'Nothing has location data yet.'
                    : 'Nothing matches the current filters.'}
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
