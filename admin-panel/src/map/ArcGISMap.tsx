import { useEffect, useRef } from 'react';
import EsriMap from '@arcgis/core/Map.js';
import MapView from '@arcgis/core/views/MapView.js';
import Popup from '@arcgis/core/widgets/Popup.js';
import { ensureArcgisReady } from '../bootstrap/arcgisSetup';
import { createWorldImageryBasemap } from './basemap';
import { toArcgisPoint } from './coords';

interface ArcGISMapProps {
  className?: string;
  center: [number, number]; // [lat, lng], initial only — uncontrolled after mount
  zoom: number;
  scrollWheelZoom?: boolean;
  onViewReady: (view: MapView) => void;
}

// React StrictMode mounts -> unmounts -> remounts in dev. Defer MapView teardown
// so the immediate remount can cancel it, instead of destroying a view that's
// about to be recreated for the exact same container.
let mountGenerationCounter = 0;
let pendingTeardownTimer: ReturnType<typeof window.setTimeout> | null = null;
let lastView: MapView | null = null;

function claimMountSession() {
  if (pendingTeardownTimer !== null) {
    window.clearTimeout(pendingTeardownTimer);
    pendingTeardownTimer = null;
    if (lastView && !lastView.destroyed) {
      lastView.destroy();
      lastView = null;
    }
  }
  mountGenerationCounter += 1;
  return mountGenerationCounter;
}

function scheduleTeardown(generation: number, teardown: () => void) {
  if (pendingTeardownTimer !== null) {
    window.clearTimeout(pendingTeardownTimer);
  }
  pendingTeardownTimer = window.setTimeout(() => {
    pendingTeardownTimer = null;
    if (generation !== mountGenerationCounter) return;
    teardown();
  }, 0);
}

export default function ArcGISMap({ className, center, zoom, scrollWheelZoom, onViewReady }: ArcGISMapProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!containerRef.current) return undefined;
    const generation = claimMountSession();
    let isDisposed = false;

    const view = new MapView({
      container: containerRef.current,
      map: new EsriMap({ basemap: createWorldImageryBasemap() }),
      center: toArcgisPoint(center[0], center[1]),
      zoom,
      popup: new Popup({ dockEnabled: false }),
    });
    view.navigation.actionMap.mouseWheel = scrollWheelZoom === false ? 'none' : 'zoom';
    // Default position (top-left) sits under the dashboard's hero stat cards,
    // making the zoom buttons invisible/unclickable there. Bottom-right is
    // free on every map that uses this component.
    view.ui.move('zoom', 'bottom-right');
    lastView = view;

    void ensureArcgisReady().then(() => view.when()).then(() => {
      if (isDisposed) return;
      onViewReady(view);
    }).catch(() => {
      // Expected under React StrictMode's dev-mode mount->unmount->remount cycle:
      // this view gets destroyed mid-load, aborting its basemap fetch. Benign —
      // the remounted view's own load will complete and call onViewReady.
    });

    return () => {
      isDisposed = true;
      scheduleTeardown(generation, () => {
        if (!view.destroyed) view.destroy();
        if (lastView === view) lastView = null;
      });
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <div ref={containerRef} className={className} style={{ height: '100%', width: '100%' }} />;
}
