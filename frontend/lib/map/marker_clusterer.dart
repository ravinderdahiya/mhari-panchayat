import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// One thing shown on the map (an asset or a complaint) in a form the
/// clusterer can group without knowing what it is.
class MapPoint {
  const MapPoint({
    required this.id,
    required this.position,
    required this.color,
    required this.severity,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isComplaint,
    required this.onTap,
  });

  final String id;
  final LatLng position;
  final Color color;

  /// 0 (fine) .. 3 (needs attention). A cluster takes the colour of its worst
  /// member, so a red bubble means "something in here needs attention".
  final int severity;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isComplaint;
  final VoidCallback onTap;
}

/// A group of [MapPoint]s that sit close together on screen. A cluster with a
/// single point is just that point.
class MapCluster {
  MapCluster(this.points)
    : center = LatLng(
        points.fold<double>(0, (sum, p) => sum + p.position.latitude) / points.length,
        points.fold<double>(0, (sum, p) => sum + p.position.longitude) / points.length,
      ),
      worst = points.reduce((a, b) => b.severity > a.severity ? b : a);

  final List<MapPoint> points;
  final LatLng center;

  /// The most severe member (first one wins a tie) - supplies the bubble colour.
  final MapPoint worst;

  int get count => points.length;
  bool get isSingle => points.length == 1;

  /// True when every member is at (practically) the same spot, so zooming in can
  /// never pull them apart.
  bool get isCoLocated {
    final first = points.first.position;

    return points.every(
      (p) => (p.position.latitude - first.latitude).abs() < 1e-6 && (p.position.longitude - first.longitude).abs() < 1e-6,
    );
  }
}

/// Groups points that are within one grid cell of each other *on screen*.
///
/// The grid lives in world-pixel space at the current zoom (not screen space), so
/// panning does not reshuffle the groups - only zooming does. Points well outside
/// the visible area are skipped, which keeps this cheap for large data sets.
List<MapCluster> clusterPoints(
  List<MapPoint> points,
  MapCamera camera, {
  double? cellPx,
  double marginPx = 96,
}) {
  final cell = cellPx ?? cellSizeForZoom(camera.zoom);
  final size = camera.size;
  final groups = <(int, int), List<MapPoint>>{};

  for (final point in points) {
    final onScreen = camera.getOffsetFromOrigin(point.position);
    if (onScreen.dx < -marginPx ||
        onScreen.dy < -marginPx ||
        onScreen.dx > size.width + marginPx ||
        onScreen.dy > size.height + marginPx) {
      continue;
    }

    final world = camera.projectAtZoom(point.position);
    groups.putIfAbsent(((world.dx / cell).floor(), (world.dy / cell).floor()), () => []).add(point);
  }

  final clusters = [for (final group in groups.values) MapCluster(group)];

  // Draw order: big, severe clusters last so they end up on top.
  clusters.sort((a, b) {
    final bySeverity = a.worst.severity.compareTo(b.worst.severity);

    return bySeverity != 0 ? bySeverity : a.count.compareTo(b.count);
  });

  return clusters;
}

/// Grid cell size in screen pixels: tighter when zoomed in, so points that are
/// genuinely apart stop being merged.
double cellSizeForZoom(double zoom) {
  if (zoom < 14) return 64;
  if (zoom < 17) return 48;

  return 38;
}

/// Diameter of a single marker for the current zoom: small dots when the whole
/// state is in view, full-size markers once the user is close.
double markerSizeForZoom(double zoom) {
  if (zoom < 9) return 12;
  if (zoom < 12) return 18;
  if (zoom < 15) return 24;

  return 30;
}

/// Diameter of a cluster bubble: grows slowly with the number of members.
double clusterSizeFor(int count) {
  final step = math.min(math.log(count + 1) / math.log(120), 1.0);

  return 28 + 14 * step;
}
