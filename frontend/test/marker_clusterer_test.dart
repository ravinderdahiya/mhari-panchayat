import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mhari_panchayat/map/marker_clusterer.dart';

MapPoint _point(String id, double lat, double lng, {int severity = 0, Color color = Colors.green}) => MapPoint(
  id: id,
  position: LatLng(lat, lng),
  color: color,
  severity: severity,
  title: id,
  subtitle: '',
  icon: Icons.place,
  isComplaint: false,
  onTap: () {},
);

MapCamera _camera(double zoom, {LatLng center = const LatLng(29.0, 76.0)}) => MapCamera(
  crs: const Epsg3857(),
  center: center,
  zoom: zoom,
  rotation: 0,
  nonRotatedSize: const Size(400, 800),
);

void main() {
  test('nearby points merge into one cluster at low zoom and separate when zoomed in', () {
    final points = [
      _point('a', 29.0000, 76.0000),
      _point('b', 29.0010, 76.0010), // ~150 m from a
      _point('c', 29.0020, 76.0000),
    ];

    final far = clusterPoints(points, _camera(9));
    expect(far, hasLength(1));
    expect(far.single.count, 3);

    final near = clusterPoints(points, _camera(18));
    expect(near, hasLength(3));
    expect(near.every((c) => c.isSingle), isTrue);
  });

  test('points far apart stay separate', () {
    final points = [_point('a', 29.0, 76.0), _point('b', 29.1, 76.1)];

    expect(clusterPoints(points, _camera(10)), hasLength(2));
  });

  test('a cluster takes the colour of its most severe member', () {
    final points = [
      _point('ok', 29.0, 76.0, severity: 0, color: Colors.green),
      _point('bad', 29.0001, 76.0001, severity: 3, color: Colors.red),
      _point('mid', 29.0002, 76.0002, severity: 1, color: Colors.amber),
    ];

    final cluster = clusterPoints(points, _camera(8)).single;
    expect(cluster.worst.id, 'bad');
    expect(cluster.worst.color, Colors.red);
  });

  test('points outside the visible area are skipped', () {
    final points = [_point('here', 29.0, 76.0), _point('elsewhere', 10.0, 40.0)];

    final clusters = clusterPoints(points, _camera(12));
    expect(clusters, hasLength(1));
    expect(clusters.single.points.single.id, 'here');
  });

  test('grouping does not change when the map is only panned', () {
    final points = [_point('a', 29.0000, 76.0000), _point('b', 29.0300, 76.0300), _point('c', 29.0302, 76.0302)];

    List<int> sizes(LatLng center) =>
        (clusterPoints(points, _camera(11, center: center))..sort((a, b) => a.count.compareTo(b.count))).map((c) => c.count).toList();

    expect(sizes(const LatLng(29.01, 76.01)), sizes(const LatLng(29.012, 76.012)));
  });

  test('co-located points are reported as such', () {
    final cluster = MapCluster([_point('a', 29.0, 76.0), _point('b', 29.0, 76.0)]);
    expect(cluster.isCoLocated, isTrue);
    expect(MapCluster([_point('a', 29.0, 76.0), _point('b', 29.001, 76.0)]).isCoLocated, isFalse);
  });

  test('marker size grows with zoom and cluster size with count', () {
    expect(markerSizeForZoom(7.7), lessThan(markerSizeForZoom(11)));
    expect(markerSizeForZoom(11), lessThan(markerSizeForZoom(16)));
    expect(clusterSizeFor(2), lessThan(clusterSizeFor(100)));
    expect(clusterSizeFor(100000), lessThanOrEqualTo(42));
  });
}
