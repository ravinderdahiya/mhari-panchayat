import esriConfig from '@arcgis/core/config.js';
import '@arcgis/core/assets/esri/themes/light/main.css';

let readyPromise: Promise<void> | null = null;

// Points the SDK at the assets copied into public/arcgis/assets by `npm run copy:arcgis`.
// No API key is set — TileLayer/FeatureLayer/GraphicsLayer (everything this app uses)
// work against public, unauthenticated Esri REST services without one.
export function ensureArcgisReady(): Promise<void> {
  if (readyPromise) return readyPromise;

  readyPromise = (async () => {
    const assetsPath = new URL(`${import.meta.env.BASE_URL}arcgis/assets/`, window.location.origin).toString();
    esriConfig.assetsPath = assetsPath;
  })();

  return readyPromise;
}
