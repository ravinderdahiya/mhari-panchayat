import 'dart:math';

import 'package:latlong2/latlong.dart';

/// One GPS fix captured while recording a route.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
    required this.time,
    this.accuracy,
  });

  final double lat;
  final double lng;
  final DateTime time;

  /// Horizontal accuracy in metres, as reported by the device.
  final double? accuracy;

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    't': time.toUtc().toIso8601String(),
    if (accuracy != null) 'accuracy': accuracy,
  };

  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    time: DateTime.parse(json['t'] as String),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
  );
}

/// A finished recording - the JSON shape saved offline (and later sent to
/// the backend).
class RouteTrack {
  const RouteTrack({
    required this.id,
    required this.uuid,
    required this.startedAt,
    required this.endedAt,
    required this.points,
    this.description = '',
    this.uploadedAt,
  });

  /// What the user said this route is for - asked (and required) at Start.
  /// Empty only for routes saved before descriptions existed.
  final String description;

  /// Local key (start time in ms) used by the offline store.
  final String id;

  /// Client-generated id sent to the server, so re-uploading the same route
  /// is recognised as a duplicate instead of creating a second polygon.
  final String uuid;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<RoutePoint> points;

  /// Set once the route has been uploaded to the server.
  final DateTime? uploadedAt;

  bool get isUploaded => uploadedAt != null;

  Duration get duration => endedAt.difference(startedAt);

  double get distanceMeters => pathDistanceMeters(points);

  RouteTrack copyWith({DateTime? uploadedAt}) => RouteTrack(
    id: id,
    uuid: uuid,
    startedAt: startedAt,
    endedAt: endedAt,
    points: points,
    description: description,
    uploadedAt: uploadedAt ?? this.uploadedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'description': description,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'distance_m': distanceMeters.round(),
    'duration_s': duration.inSeconds,
    if (uploadedAt != null) 'uploaded_at': uploadedAt!.toUtc().toIso8601String(),
    'points': [for (final p in points) p.toJson()],
  };

  factory RouteTrack.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final uploaded = json['uploaded_at'] as String?;
    return RouteTrack(
      id: id,
      // Routes saved before uuids existed get a stable one derived from id.
      uuid: json['uuid'] as String? ?? uuidFromId(id),
      description: json['description'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.parse(json['ended_at'] as String),
      points: [
        for (final p in json['points'] as List)
          RoutePoint.fromJson(p as Map<String, dynamic>),
      ],
      uploadedAt: uploaded == null ? null : DateTime.parse(uploaded),
    );
  }
}

String _formatUuid(List<int> b) {
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String generateUuid() {
  final random = Random.secure();
  return _formatUuid(List<int>.generate(16, (_) => random.nextInt(256)));
}

/// Deterministic uuid for a route that only has the old millisecond id.
String uuidFromId(String id) {
  var n = int.tryParse(id) ?? id.hashCode;
  final bytes = List<int>.filled(16, 0);
  for (var i = 15; i >= 10; i--) {
    bytes[i] = n & 0xff;
    n >>= 8;
  }
  return _formatUuid(bytes);
}

double pathDistanceMeters(List<RoutePoint> points) {
  const distance = Distance();
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distance.as(LengthUnit.Meter, points[i - 1].latLng, points[i].latLng);
  }
  return total;
}

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(2)} km';

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
