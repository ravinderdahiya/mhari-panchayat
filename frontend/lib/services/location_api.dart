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

class LocationApi {
  LocationApi._();

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
