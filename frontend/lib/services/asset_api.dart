import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/asset.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class AssetApiException implements Exception {
  AssetApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to `/api/assets` on the Gram Samadhan backend — surveyed assets
/// surfaced to citizens on the map, in the nearby-search flow, and in the
/// details screen.
class AssetApi {
  AssetApi._();

  static Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${ApiConfig.baseUrl}/api/assets$path',
  ).replace(queryParameters: query);

  static Future<Map<String, dynamic>> _get(Uri uri) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw AssetApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw AssetApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode == 401) {
      await SessionGuard.handleUnauthorized();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AssetApiException(
        body['message'] as String? ?? 'एसेट लोड नहीं हो पाए। पुनः प्रयास करें।',
      );
    }

    return body;
  }

  static Future<List<AssetSummary>> getAssets() async {
    final body = await _get(_uri(''));
    final assets = body['assets'] as List<dynamic>? ?? const [];
    return assets
        .map((item) => AssetSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Every active asset within [radiusMeters] of (lat, lng), nearest first.
  /// Never picks a single "best" match — the citizen always confirms one.
  static Future<List<AssetNearby>> getNearbyAssets({
    required double latitude,
    required double longitude,
    double radiusMeters = 100,
  }) async {
    final body = await _get(
      _uri('/nearby', {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius': radiusMeters.toString(),
      }),
    );
    final assets = body['assets'] as List<dynamic>? ?? const [];
    return assets
        .map((item) => AssetNearby.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<AssetDetail> getAssetById(String id) async {
    final body = await _get(_uri('/$id'));
    final asset = body['asset'] as Map<String, dynamic>? ?? const {};
    return AssetDetail.fromJson(asset);
  }
}
