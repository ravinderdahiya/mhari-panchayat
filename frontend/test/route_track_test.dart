import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mhari_panchayat/models/route_track.dart';
import 'package:mhari_panchayat/services/route_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

RouteTrack _track(String id) {
  final start = DateTime.utc(2026, 10, 5, 6, 0, 0);
  return RouteTrack(
    id: id,
    uuid: generateUuid(),
    startedAt: start,
    endedAt: start.add(const Duration(seconds: 12)),
    points: [
      RoutePoint(lat: 29.0, lng: 76.0, time: start, accuracy: 5),
      RoutePoint(
        lat: 29.001,
        lng: 76.0,
        time: start.add(const Duration(seconds: 4)),
      ),
      RoutePoint(
        lat: 29.002,
        lng: 76.0,
        time: start.add(const Duration(seconds: 8)),
      ),
    ],
  );
}

void main() {
  test('distance and duration are computed from the points', () {
    final track = _track('a');
    // 0.002 degrees of latitude is roughly 222 m.
    expect(track.distanceMeters, closeTo(222, 3));
    expect(track.duration, const Duration(seconds: 12));
  });

  test('JSON round trip keeps every point', () {
    final json = jsonDecode(jsonEncode(_track('a').toJson()));
    final back = RouteTrack.fromJson(json as Map<String, dynamic>);
    expect(back.points.length, 3);
    expect(back.points.first.accuracy, 5);
    expect(back.points.last.lat, 29.002);
    expect(json['distance_m'], 222);
  });

  test('store saves newest first and deletes by id', () async {
    SharedPreferences.setMockInitialValues({});
    await RouteStore.save(_track('first'));
    await RouteStore.save(_track('second'));
    expect((await RouteStore.load()).map((t) => t.id), ['second', 'first']);

    await RouteStore.delete('second');
    expect((await RouteStore.load()).map((t) => t.id), ['first']);
  });

  test('description survives JSON and defaults to empty for old routes', () {
    final withDesc = RouteTrack(
      id: 'd',
      uuid: generateUuid(),
      description: 'Boundary of Ramlal field',
      startedAt: DateTime.utc(2026, 10, 5),
      endedAt: DateTime.utc(2026, 10, 5, 0, 1),
      points: const [],
    );
    final json = jsonDecode(jsonEncode(withDesc.toJson())) as Map<String, dynamic>;
    expect(RouteTrack.fromJson(json).description, 'Boundary of Ramlal field');

    json.remove('description');
    expect(RouteTrack.fromJson(json).description, '');
  });

  test('uuids are valid and old routes get a stable one', () {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(generateUuid(), matches(uuid));
    expect(generateUuid(), isNot(generateUuid()));
    expect(uuidFromId('1790000000000'), matches(uuid));
    expect(uuidFromId('1790000000000'), uuidFromId('1790000000000'));
    expect(uuidFromId('1790000000000'), isNot(uuidFromId('1790000000001')));
  });

  test('markUploaded keeps the route and flags it uploaded', () async {
    SharedPreferences.setMockInitialValues({});
    final track = _track('u1');
    await RouteStore.save(track);
    expect((await RouteStore.load()).single.isUploaded, false);

    await RouteStore.markUploaded('u1', DateTime.utc(2026, 10, 5, 7));
    final loaded = (await RouteStore.load()).single;
    expect(loaded.isUploaded, true);
    expect(loaded.uuid, track.uuid);
    expect(loaded.points.length, 3);
  });

  test('formatters', () {
    expect(formatDistance(480), '480 m');
    expect(formatDistance(1500), '1.50 km');
    expect(formatDuration(const Duration(seconds: 75)), '01:15');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
  });
}
