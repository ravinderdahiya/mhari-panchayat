import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/survey.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class SurveyReviewApiException implements Exception {
  SurveyReviewApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Verification side of `/api/surveys` - the escalation-chain queue shared
/// by Gram Sachiv, BDPO, DDPO, XEN-PR and CEO-ZP (backend auto-scopes each
/// caller to their own jurisdiction - panchayat/block/district - so this
/// never has to pass a location filter itself).
class SurveyReviewApi {
  SurveyReviewApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/surveys$path');

  static Future<Map<String, String>> _authHeaders() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw SurveyReviewApiException('कृपया पहले लॉगिन करें');
    }
    return {'Authorization': 'Bearer ${session.token}'};
  }

  static Future<Map<String, dynamic>> _decode(http.Response response) async {
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
      throw SurveyReviewApiException(
        body['message'] as String? ?? 'अनुरोध पूरा नहीं हो पाया।',
      );
    }
    return body;
  }

  /// `reviewStatus` one of pending/returned/gram_sachiv_approved/
  /// bdpo_forwarded/approved/rejected, or null for all.
  static Future<List<Survey>> getQueue({String? reviewStatus}) async {
    final headers = await _authHeaders();
    final uri = reviewStatus == null
        ? _uri('')
        : _uri('').replace(queryParameters: {'review_status': reviewStatus});

    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    final body = await _decode(response);
    final surveys = body['surveys'] as List<dynamic>? ?? const [];
    return surveys
        .map((item) => Survey.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Gram Sachiv's positive action on a pending survey - sends it on to
  /// BDPO. Named `verify` (not `approve`) because `/approve` is reserved
  /// for DDPO's final sign-off further down the chain.
  static Future<Survey> verify(String surveyId) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/verify'), headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  static Future<Survey> returnForCorrection(String surveyId, String reason) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/return'), headers: headers, body: {'reason': reason})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  /// BDPO's positive action - sends a gram-sachiv-verified survey on to DDPO.
  static Future<Survey> forward(String surveyId) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/forward'), headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  /// DDPO's positive action - sends technical asset types on to XEN-PR and
  /// everything else straight to CEO-ZP.
  static Future<Survey> approve(String surveyId) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/approve'), headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  /// XEN-PR's technical sign-off, only reachable for asset types that
  /// require it - sends the survey on to CEO-ZP.
  static Future<Survey> technicalReview(String surveyId) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/technical-review'), headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  /// CEO-ZP's final sign-off, closing the verification chain.
  static Future<Survey> finalApprove(String surveyId) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/final-approve'), headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }

  static Future<Survey> reject(String surveyId, String reason) async {
    final headers = await _authHeaders();
    late final http.Response response;
    try {
      response = await http
          .post(_uri('/$surveyId/reject'), headers: headers, body: {'reason': reason})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw SurveyReviewApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = await _decode(response);
    return Survey.fromJson(body['survey'] as Map<String, dynamic>? ?? const {});
  }
}
