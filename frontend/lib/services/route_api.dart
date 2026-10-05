import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/route_track.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class RouteApiException implements Exception {
  RouteApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Uploads recorded routes to `POST /api/polygons` (GPS points in, polygon
/// out). Sends the route's client-generated uuid so uploading the same route
/// twice is treated as a duplicate by the server, not a second polygon.
class RouteApi {
  RouteApi._();

  static Uri get _uri => Uri.parse('${ApiConfig.baseUrl}/api/polygons');

  /// Local time with its UTC offset, e.g. `2026-10-05T10:00:03+05:30` - the
  /// format the API documents (a bare `Z` timestamp is not what it shows).
  static String _stamp(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final iso = local.toIso8601String().split('.').first;
    return '$iso$sign${two(abs.inHours)}:${two(abs.inMinutes.remainder(60))}';
  }

  static Map<String, dynamic> _body(RouteTrack track) => {
    'uuid': track.uuid,
    'started_at': _stamp(track.startedAt),
    'ended_at': _stamp(track.endedAt),
    'points': [
      for (final p in track.points)
        {
          'lat': p.lat,
          'lng': p.lng,
          if (p.accuracy != null) 'accuracy': p.accuracy,
          'timestamp': _stamp(p.time),
        },
    ],
  };

  /// Returns normally when the route is on the server (including when the
  /// server says it already had it); throws [RouteApiException] otherwise.
  static Future<void> upload(RouteTrack track) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw RouteApiException('Please log in first.');
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _uri,
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_body(track)),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw RouteApiException(
        'Could not reach the server. Check your internet and try again.',
      );
    }

    // Helps diagnose server-side failures from `flutter run` logs.
    debugPrint(
      'POST /api/polygons -> ${response.statusCode} ${response.body}',
    );

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode == 401) {
      await SessionGuard.handleUnauthorized();
    }

    final message = body['message'] as String?;
    final isDuplicate =
        response.statusCode == 409 ||
        (message?.toLowerCase().contains('duplicate') ?? false);
    if (isDuplicate) return;

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] == false) {
      throw RouteApiException(
        _firstError(body['errors']) ?? message ?? 'Upload failed. Try again.',
        statusCode: response.statusCode,
      );
    }
  }

  /// Laravel validation errors come as {field: [msg, ...]}.
  static String? _firstError(Object? errors) {
    if (errors is! Map) return null;
    for (final value in errors.values) {
      if (value is List && value.isNotEmpty) return value.first.toString();
      if (value is String) return value;
    }
    return null;
  }
}
