import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class FeedbackApiException implements Exception {
  FeedbackApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Talks to `/api/feedback` on the Gram Samadhan backend - staff sharing
/// in-app feedback (bug/suggestion/complaint/general), with an optional
/// star rating and screenshot.
class FeedbackApi {
  FeedbackApi._();

  static Uri get _uri => Uri.parse('${ApiConfig.baseUrl}/api/feedback');

  static Future<void> submit({
    required String category,
    required String message,
    int? rating,
    Uint8List? photo,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw FeedbackApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      final request = http.MultipartRequest('POST', _uri)
        ..headers['Authorization'] = 'Bearer ${session.token}'
        ..fields.addAll({
          'category': category,
          'message': message,
          if (rating != null) 'rating': rating.toString(),
        });

      if (photo != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            photo,
            filename: 'feedback_photo.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw FeedbackApiException(
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
      throw FeedbackApiException(
        body['message'] as String? ?? 'Feedback भेजा नहीं जा सका। पुनः प्रयास करें।',
        statusCode: response.statusCode,
      );
    }
  }
}
