import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/route_track.dart';

/// Offline storage for recorded routes. Uses shared_preferences (already a
/// dependency, and works on mobile and web alike) - each route is kept as
/// one JSON string, newest first.
class RouteStore {
  RouteStore._();

  static const _key = 'saved_routes_v1';

  static Future<List<RouteTrack>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final tracks = <RouteTrack>[];
    for (final item in raw) {
      try {
        tracks.add(
          RouteTrack.fromJson(jsonDecode(item) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip an entry that can't be parsed rather than hiding the rest.
      }
    }
    return tracks;
  }

  static Future<void> save(RouteTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    await prefs.setStringList(_key, [jsonEncode(track.toJson()), ...raw]);
  }

  /// Records that [id] was uploaded, keeping the rest of the entry as is.
  static Future<RouteTrack?> markUploaded(String id, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    RouteTrack? updated;
    final next = <String>[];
    for (final item in raw) {
      try {
        final track = RouteTrack.fromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
        if (track.id == id) {
          updated = track.copyWith(uploadedAt: when);
          next.add(jsonEncode(updated.toJson()));
          continue;
        }
      } catch (_) {}
      next.add(item);
    }
    await prefs.setStringList(_key, next);
    return updated;
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = <String>[];
    for (final item in prefs.getStringList(_key) ?? const <String>[]) {
      try {
        if ((jsonDecode(item) as Map<String, dynamic>)['id'] == id) continue;
      } catch (_) {}
      kept.add(item);
    }
    await prefs.setStringList(_key, kept);
  }
}
