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

  /// Number of unread notifications. Quiet on purpose: it is polled in the
  /// background, so it never triggers the session-expired flow and just throws
  /// when the call fails.
  static Future<int> unreadCount() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw NotificationApiException('Not logged in');
    }

    final response = await http
        .get(_uri('/unread-count'), headers: {'Authorization': 'Bearer ${session.token}'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException('Could not load the unread count');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return (body['count'] as num?)?.toInt() ?? 0;
  }

  /// Registers this phone's push token for the signed-in user (a token moves to
  /// whoever registered it last). Quiet like [unreadCount]: throws on failure.
  static Future<void> registerDevice(String token) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw NotificationApiException('Not logged in');
    }

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/device-tokens'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'token': token, 'platform': 'android'}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException('Could not register the device');
    }
  }

  /// Stops pushes to this phone for the signed-in user (call before logout).
  static Future<void> unregisterDevice(String token) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) return;

    await http
        .delete(
          Uri.parse('${ApiConfig.baseUrl}/api/device-tokens'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 10));
  }

  static Future<void> markAllRead() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw NotificationApiException('कृपया पहले लॉगिन करें');
    }

    try {
      final response = await http
          .patch(_uri('/read-all'), headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NotificationApiException('सभी सूचनाएं पढ़ी हुई नहीं की जा सकीं।');
      }
    } on NotificationApiException {
      rethrow;
    } catch (_) {
      throw NotificationApiException('Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।');
    }
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
