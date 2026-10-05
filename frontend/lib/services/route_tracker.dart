import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_track.dart';
import 'fake_location_detector.dart';

/// Records the user's position at a fixed interval while a route is being
/// walked. A singleton so recording keeps running when the user switches
/// tabs or opens another screen; the map screen just listens and draws.
///
/// Foreground only: the timer runs while the app is open (screen on).
class RouteTracker extends ChangeNotifier {
  RouteTracker._();

  static final RouteTracker instance = RouteTracker._();

  /// One GPS fix every 3 seconds.
  static const interval = Duration(seconds: 3);

  Timer? _timer;
  DateTime? _startedAt;
  final List<RoutePoint> _points = [];
  double _distance = 0;
  bool _capturing = false;

  bool get isRecording => _timer != null;
  DateTime? get startedAt => _startedAt;
  List<RoutePoint> get points => List.unmodifiable(_points);
  double get distanceMeters => _distance;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Starts recording. Returns an error message, or null on success.
  Future<String?> start() async {
    if (isRecording) return null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Please turn on location (GPS) first.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Location permission is required to record a route.';
    }
    if (await FakeLocationDetector.isFakeLocation()) {
      return 'Fake/mock location detected. Turn it off to record a route.';
    }

    _points.clear();
    _distance = 0;
    _startedAt = DateTime.now();

    if (!await _capture()) {
      _startedAt = null;
      return 'Could not read your location. Try again outdoors.';
    }
    _timer = Timer.periodic(interval, (_) => _capture());
    notifyListeners();
    return null;
  }

  /// Stops recording and returns the finished route, or null if no point
  /// was captured. The caller decides whether to save it.
  RouteTrack? stop() {
    _timer?.cancel();
    _timer = null;

    final startedAt = _startedAt;
    final track = (startedAt == null || _points.isEmpty)
        ? null
        : RouteTrack(
            id: startedAt.millisecondsSinceEpoch.toString(),
            uuid: generateUuid(),
            startedAt: startedAt,
            endedAt: DateTime.now(),
            points: List.of(_points),
          );

    _points.clear();
    _distance = 0;
    _startedAt = null;
    notifyListeners();
    return track;
  }

  Future<bool> _capture() async {
    if (_capturing) return true;
    _capturing = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      // stop() may have run while waiting for the fix.
      if (_startedAt == null) return true;

      final point = RoutePoint(
        lat: position.latitude,
        lng: position.longitude,
        time: DateTime.now(),
        accuracy: position.accuracy,
      );
      if (_points.isNotEmpty) {
        _distance += const Distance().as(
          LengthUnit.Meter,
          _points.last.latLng,
          point.latLng,
        );
      }
      _points.add(point);
      notifyListeners();
      return true;
    } catch (_) {
      // A single missed fix shouldn't end the recording.
      return false;
    } finally {
      _capturing = false;
    }
  }
}
