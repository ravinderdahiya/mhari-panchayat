import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

class DetectedLocation {
  const DetectedLocation({
    this.districtId,
    this.district,
    this.tehsilId,
    this.tehsil,
    this.villageId,
    this.village,
    this.panchayatId,
    this.panchayat,
  });

  final int? districtId;
  final String? district;
  final int? tehsilId;
  final String? tehsil;
  final int? villageId;
  final String? village;
  final int? panchayatId;
  final String? panchayat;
}

/// One hit of the map's place search (district / block / panchayat / village).
class PlaceHit {
  const PlaceHit({
    required this.level,
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final String level;
  final int id;
  final String name;
  final String subtitle;
}

/// Bounding box in WGS84 degrees.
typedef GeoExtent = ({double xmin, double ymin, double xmax, double ymax});

class LocationApi {
  LocationApi._();

  /// Type-ahead search over the Haryana hierarchy. [level] narrows it to
  /// 'district' | 'block' | 'panchayat' | 'village'. Returns [] on any failure.
  static Future<List<PlaceHit>> search(String query, {String? level}) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) return const [];

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/location/search').replace(
      queryParameters: {'q': query.trim(), if (level != null) 'level': level},
    );
    final body = await _getJson(uri, session.token);
    final results = body?['results'];
    if (results is! List) return const [];

    return [
      for (final item in results.whereType<Map<String, dynamic>>())
        if (int.tryParse('${item['id']}') != null)
          PlaceHit(
            level: '${item['level']}',
            id: int.parse('${item['id']}'),
            name: '${item['name']}',
            subtitle: '${item['subtitle'] ?? ''}',
          ),
    ];
  }

  /// Real boundary extent of a searched place, or null when it has none.
  static Future<GeoExtent?> extent({required String level, required int id}) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) return null;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/location/extent').replace(
      queryParameters: {'level': level, 'id': '$id'},
    );
    final extent = (await _getJson(uri, session.token))?['extent'];
    if (extent is! Map) return null;

    double? number(String key) => double.tryParse('${extent[key]}');
    final xmin = number('xmin'), ymin = number('ymin');
    final xmax = number('xmax'), ymax = number('ymax');
    if (xmin == null || ymin == null || xmax == null || ymax == null) return null;

    return (xmin: xmin, ymin: ymin, xmax: xmax, ymax: ymax);
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri, String token) async {
    try {
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = jsonDecode(response.body);

      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  static Future<DetectedLocation?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) return null;

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/location/reverse').replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
      },
    );
    return _get(uri, session.token);
  }

  static Future<DetectedLocation?> resolve({
    String? district,
    String? tehsil,
    String? village,
    String? panchayat,
    String? administrativeArea,
    String? subAdministrativeArea,
    String? locality,
    String? subLocality,
    String? name,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) return null;

    final values = <String, String>{
      if (district?.trim().isNotEmpty ?? false) 'district': district!.trim(),
      if (tehsil?.trim().isNotEmpty ?? false) 'tehsil': tehsil!.trim(),
      if (village?.trim().isNotEmpty ?? false) 'village': village!.trim(),
      if (panchayat?.trim().isNotEmpty ?? false) 'panchayat': panchayat!.trim(),
      if (administrativeArea?.trim().isNotEmpty ?? false)
        'administrative_area': administrativeArea!.trim(),
      if (subAdministrativeArea?.trim().isNotEmpty ?? false)
        'sub_administrative_area': subAdministrativeArea!.trim(),
      if (locality?.trim().isNotEmpty ?? false) 'locality': locality!.trim(),
      if (subLocality?.trim().isNotEmpty ?? false)
        'sub_locality': subLocality!.trim(),
      if (name?.trim().isNotEmpty ?? false) 'name': name!.trim(),
    };
    if (values.isEmpty) return null;
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/location/resolve',
    ).replace(queryParameters: values);
    return _get(uri, session.token);
  }

  static Future<DetectedLocation?> _get(Uri uri, String token) async {
    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final location = body['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    String? value(String key) {
      final text = location[key]?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    int? id(String key) => int.tryParse(location[key]?.toString() ?? '');

    return DetectedLocation(
      districtId: id('districtId'),
      district: value('district'),
      tehsilId: id('tehsilId'),
      tehsil: value('tehsil'),
      villageId: id('villageId'),
      panchayat: value('panchayat'),
      village: value('village'),
      panchayatId: id('panchayatId'),
    );
  }
}
