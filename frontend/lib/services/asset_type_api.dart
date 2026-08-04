import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/asset_type.dart';
import '../models/survey.dart';
import '../models/survey_department.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class AssetTypeApiException implements Exception {
  AssetTypeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Survey flow: pick department → load assets for that department.
class AssetTypeApi {
  AssetTypeApi._();

  static Future<Map<String, String>> _authHeaders() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw AssetTypeApiException('कृपया पहले लॉगिन करें');
    }
    return {
      'Authorization': 'Bearer ${session.token}',
      'Accept': 'application/json',
    };
  }

  static Future<Map<String, dynamic>> _get(Uri uri) async {
    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw AssetTypeApiException(
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
      throw AssetTypeApiException(
        body['message'] as String? ?? 'Request failed (${response.statusCode})',
      );
    }
    return body;
  }

  static Future<List<SurveyDepartment>> getDepartments() async {
    final body = await _get(
      Uri.parse('${ApiConfig.baseUrl}/api/survey-departments'),
    );
    final items = body['departments'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) =>
              SurveyDepartment.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where((d) => d.id > 0)
        .toList();
  }

  static Future<List<AssetType>> getAssetTypes({
    required int departmentId,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/asset-types',
    ).replace(queryParameters: {'department_id': departmentId.toString()});
    final body = await _get(uri);
    final items = body['assetTypes'] as List<dynamic>? ?? const [];
    final types = items
        .map(
          (item) => AssetType.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return types;
  }

  static Future<List<SurveyConditionOption>> getSurveyConditions() async {
    final body = await _get(
      Uri.parse('${ApiConfig.baseUrl}/api/survey-options'),
    );
    final items = body['conditions'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) => SurveyConditionOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((option) => option.label.isNotEmpty)
        .toList();
  }
}
