import { useEffect, useRef, useState } from 'react';
import type MapView from '@arcgis/core/views/MapView.js';
import Graphic from '@arcgis/core/Graphic.js';
import GraphicsLayer from '@arcgis/core/layers/GraphicsLayer.js';
import MapImageLayer from '@arcgis/core/layers/MapImageLayer.js';
import ArcGISMap from '../map/ArcGISMap';
import { dotSymbol } from '../map/symbols';
import { toArcgisPoint } from '../map/coords';
import * as api from '../services/api';
import type { PublicAssetPoint } from '../services/api';
import type { Lang } from './strings';

type T = (key: string, vars?: Record<string, string | number>) => string;

export interface MapFilters {
  district_id?: number;
  block_id?: number;
  panchayat_id?: number;
}

interface Props {
  t: T;
  lang: Lang;
  filters: MapFilters;
}

const HARYANA_CENTER: [number, number] = [29.0, 76.1];

/** The public asset map: HARSAC's panchayat boundary under the approved asset points. */
export default function HomeMap({ t, lang, filters }: Props) {
  const [view, setView] = useState<MapView | null>(null);
  const [points, setPoints] = useState<PublicAssetPoint[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const layerRef = useRef<GraphicsLayer | null>(null);

  // Boundary + points layers, added once the view exists.
  useEffect(() => {
    if (!view?.map) return undefined;
    const boundary = new MapImageLayer({ url: api.gisPanchayatMapServerUrl });
    const layer = new GraphicsLayer();
    view.map.addMany([boundary, layer]);
    layerRef.current = layer;
    return () => {
      if (view.map) view.map.removeMany([boundary, layer]);
      layerRef.current = null;
    };
  }, [view]);

  // Asset points for the chosen area.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    api.getPublicAssets(filters)
      .then((res) => {
        if (cancelled) return;
        setPoints(res.data.points);
        setTotal(res.data.total);
      })
      .catch(() => {
        if (!cancelled) { setPoints([]); setTotal(0); }
      })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [filters.district_id, filters.block_id, filters.panchayat_id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Draw the points and frame them.
  useEffect(() => {
    const layer = layerRef.current;
    if (!view || !layer) return;
    layer.removeAll();
    const graphics = points.map((p) => new Graphic({
      geometry: toArcgisPoint(p.lat, p.lng),
      symbol: dotSymbol('#C68A16'),
      attributes: { name: p.name, type: (lang === 'hi' ? p.type_hi : null) ?? p.type ?? '', village: p.village ?? '' },
      popupTemplate: { title: '{name}', content: '{type}<br/>{village}' },
    }));
    layer.addMany(graphics);
    if (graphics.length > 0) {
      const target = graphics.length === 1 ? { target: graphics[0], zoom: 15 } : graphics;
      void view.goTo(target, { duration: 400 }).catch(() => {});
    } else if (!filters.district_id) {
      void view.goTo({ center: [HARYANA_CENTER[1], HARYANA_CENTER[0]], zoom: 7 }, { duration: 300 }).catch(() => {});
    }
  }, [view, points, lang, filters.district_id]);

  const countText = total > points.length
    ? t('mapCountMore', { n: total, m: points.length })
    : total === 1 ? t('mapCountOne') : t('mapCount', { n: total });

  return (
    <div className="relative h-full min-h-[22rem] rounded-2xl overflow-hidden border border-line bg-white">
      <ArcGISMap center={HARYANA_CENTER} zoom={7} scrollWheelZoom={false} onViewReady={setView} />
      <div className="absolute left-3 bottom-3 z-10 rounded-lg bg-white/95 border border-line px-3 py-2 text-xs shadow-sm">
        <div className="flex items-center gap-2 text-sidebar font-semibold">
          <span className="inline-block h-2.5 w-2.5 rounded-full bg-accent border border-white shadow" />
          {loading ? t('mapLoading') : total === 0 ? t('mapEmpty') : countText}
        </div>
      </div>
    </div>
  );
}
