import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/officer_summary.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class OfficerApiException implements Exception {
  OfficerApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to `/api/officers` on the Gram Samadhan backend.
class OfficerApi {
  OfficerApi._();

  static Uri get _uri => Uri.parse('${ApiConfig.baseUrl}/api/officers');

  /// Officer-only: lists every officer, for the complaint assignment picker.
  static Future<List<OfficerSummary>> getOfficers() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw OfficerApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(_uri, headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw OfficerApiException(
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
      throw OfficerApiException(
        body['message'] as String? ??
            'अधिकारी सूची लोड नहीं हो पाई। पुनः प्रयास करें।',
      );
    }

    final officers = body['officers'] as List<dynamic>? ?? const [];
    return officers
        .map((item) => OfficerSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
