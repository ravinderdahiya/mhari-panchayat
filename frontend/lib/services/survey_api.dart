import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../config/api_config.dart';
import '../models/asset_type.dart';
import '../models/survey.dart';
import '../models/survey_department.dart';
import 'asset_type_api.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class SurveyApiException implements Exception {
  SurveyApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to `/api/surveys` on the Gram Samadhan backend for the officer
/// asset-survey flow.
class SurveyApi {
  SurveyApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/surveys$path');

  /// Departments assigned to this surveyor, then assets for the picked department.
  static Future<List<SurveyDepartment>> getSurveyDepartments() =>
      AssetTypeApi.getDepartments();

  static Future<List<AssetType>> getAssetTypes({required int departmentId}) =>
      AssetTypeApi.getAssetTypes(departmentId: departmentId);

  static Future<List<SurveyConditionOption>> getSurveyConditions() =>
      AssetTypeApi.getSurveyConditions();

  static Future<Survey> submitSurvey({
    String? surveyId,
    required int departmentId,
    required String assetTypeId,
    required String assetName,
    required String district,
    required String panchayat,
    required String village,
    double? latitude,
    double? longitude,
    String? description,
    required SurveyCondition condition,
    required DateTime surveyDate,
    required List<Uint8List> photos,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw SurveyApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      final request =
          http.MultipartRequest(
              'POST',
              _uri(surveyId == null ? '' : '/$surveyId'),
            )
            ..headers['Authorization'] = 'Bearer ${session.token}'
            ..fields.addAll({
              if (surveyId != null) '_method': 'PUT',
              'departmentId': departmentId.toString(),
              'assetTypeId': assetTypeId,
              'assetName': assetName,
              'district': district,
              'panchayat': panchayat,
              'village': village,
              if (latitude != null) 'latitude': latitude.toString(),
              if (longitude != null) 'longitude': longitude.toString(),
              if (description != null && description.isNotEmpty)
                'description': description,
              'condition': condition.wireValue,
              'surveyDate': surveyDate.toIso8601String(),
            });

      for (var i = 0; i < photos.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos[]',
            photos[i],
            filename: 'survey_photo_$i.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw SurveyApiException(
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
      throw SurveyApiException(
        body['message'] as String? ??
            'सर्वे दर्ज नहीं हो पाया। पुनः प्रयास करें।',
      );
    }

    final survey = body['survey'] as Map<String, dynamic>? ?? const {};
    return Survey.fromJson(survey);
  }

  /// Fetches all surveys submitted by the signed-in officer, newest first.
  static Future<List<Survey>> getExistingAssets() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw SurveyApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(_uri(''), headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyApiException(
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
      throw SurveyApiException(
        body['message'] as String? ??
            'सर्वे लोड नहीं हो पाए। पुनः प्रयास करें।',
      );
    }

    final surveys = body['surveys'] as List<dynamic>? ?? const [];
    return surveys
        .map((item) => Survey.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Surveys of a given asset type, from the signed-in officer's own
  /// submissions.
  static Future<List<Survey>> getAssetTypeInstances(String assetTypeId) async {
    final all = await getExistingAssets();
    return all.where((s) => s.assetTypeId == assetTypeId).toList();
  }
}
