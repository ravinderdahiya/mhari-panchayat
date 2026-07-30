import Basemap from '@arcgis/core/Basemap.js';
import TileLayer from '@arcgis/core/layers/TileLayer.js';

// Hand-built from a raw TileLayer against Esri's public World Imagery MapServer —
// deliberately NOT one of the SDK's named basemap strings ("satellite"/"hybrid"),
// which pull from cdn.arcgis.com and require an API key. This one doesn't.
export function createWorldImageryBasemap(): Basemap {
  return new Basemap({
    baseLayers: [
      new TileLayer({ url: 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer' }),
    ],
    title: 'World Imagery',
  });
}

// Same reasoning as above - a hand-built TileLayer against Esri's public
// World Street Map MapServer, not the SDK's "streets" named basemap, so this
// also needs no API key.
export function createStreetsBasemap(): Basemap {
  return new Basemap({
    baseLayers: [
      new TileLayer({ url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer' }),
    ],
    title: 'World Street Map',
  });
}
