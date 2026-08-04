import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/app_notification.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class NotificationApiException implements Exception {
  NotificationApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to `/api/notifications` on the Gram Samadhan backend.
class NotificationApi {
  NotificationApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/notifications$path');

  static Future<List<AppNotification>> getMine() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw NotificationApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(_uri(''), headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw NotificationApiException(
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
      throw NotificationApiException(
        body['message'] as String? ??
            'सूचनाएं लोड नहीं हो पाईं। पुनः प्रयास करें।',
      );
    }

    final notifications = body['notifications'] as List<dynamic>? ?? const [];
    return notifications
        .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> markRead(String id) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw NotificationApiException('कृपया पहले लॉगिन करें');
    }

    try {
      await http
          .patch(
            _uri('/$id/read'),
            headers: {'Authorization': 'Bearer ${session.token}'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw NotificationApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
  }
}
