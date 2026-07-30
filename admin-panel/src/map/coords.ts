import Point from '@arcgis/core/geometry/Point.js';

// App state is lat-first everywhere ([lat, lng] tuples, `lat`/`long` fields).
// ArcGIS geometries are x/y = longitude/latitude. Centralized here so no call
// site has to remember the order by hand.

export function toArcgisXY(lat: number, lng: number): [number, number] {
  return [lng, lat];
}

export function toArcgisPoint(lat: number, lng: number): Point {
  return new Point({ longitude: lng, latitude: lat });
}

export function fromArcgisPoint(point: Point): [number, number] {
  return [point.latitude!, point.longitude!];
}
