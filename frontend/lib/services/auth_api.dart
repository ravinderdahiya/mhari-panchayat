import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class AuthApiException implements Exception {
  AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OtpSendResult {
  const OtpSendResult({
    required this.message,
    required this.smsSent,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });

  final String message;
  final bool smsSent;
  final int expiresInSeconds;
  final int resendAfterSeconds;
}

class OtpVerifyResult {
  const OtpVerifyResult({required this.token, required this.mobile});

  final String token;
  final String mobile;
}

class StaffLoginResult {
  const StaffLoginResult({
    required this.token,
    required this.id,
    required this.staffId,
    required this.role,
    this.name,
    this.officerProfileId,
  });

  final String token;
  final String id;
  final String staffId;
  final String role;
  final String? name;

  /// The Officer table's own id (distinct from the login User id) —
  /// null for non-OFFICER staff (e.g. SURVEYOR).
  final String? officerProfileId;
}

class UserProfile {
  const UserProfile({
    required this.id,
    this.mobile,
    this.staffId,
    this.name,
    required this.role,
  });

  final String id;
  final String? mobile;
  final String? staffId;
  final String? name;
  final String role;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      mobile: json['mobile'] as String?,
      staffId:
          json['username'] as String? ??
          json['staffId'] as String? ??
          json['employee_id'] as String?,
      name: json['name'] as String?,
      role: json['role'] as String? ?? 'citizen',
    );
  }
}

/// Talks to `/api/auth` on the Gram Samadhan backend for the citizen
/// mobile-number + OTP login flow.
class AuthApi {
  AuthApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/auth$path');

  static Future<OtpSendResult> sendOtp(String mobile) async {
    final body = await _post('/send-otp', {'mobile': mobile});
    final smsSent = body['smsSent'] as bool? ?? false;
    final warning = body['warning'] as String?;
    return OtpSendResult(
      message:
          warning ??
          (body['message'] as String? ??
              (smsSent
                  ? 'OTP sent'
                  : 'OTP generated but SMS was not delivered')),
      smsSent: smsSent,
      expiresInSeconds: (body['expiresIn'] as num?)?.toInt() ?? 600,
      resendAfterSeconds: (body['resendAfter'] as num?)?.toInt() ?? 30,
    );
  }

  static Future<OtpSendResult> resendOtp(String mobile) async {
    final body = await _post('/resend-otp', {'mobile': mobile});
    final smsSent = body['smsSent'] as bool? ?? false;
    final warning = body['warning'] as String?;
    return OtpSendResult(
      message:
          warning ??
          (body['message'] as String? ??
              (smsSent
                  ? 'OTP resent'
                  : 'OTP generated but SMS was not delivered')),
      smsSent: smsSent,
      expiresInSeconds: (body['expiresIn'] as num?)?.toInt() ?? 600,
      resendAfterSeconds: (body['resendAfter'] as num?)?.toInt() ?? 30,
    );
  }

  static Future<OtpVerifyResult> verifyOtp(String mobile, String otp) async {
    final body = await _post('/verify-otp', {'mobile': mobile, 'otp': otp});
    final user = body['user'] as Map<String, dynamic>?;
    return OtpVerifyResult(
      token: body['token'] as String? ?? '',
      mobile: user?['mobile'] as String? ?? mobile,
    );
  }

  /// Staff login against mhari-panchayat `POST /api/auth/login`
  /// (username + password). Roles like `engineer` map to survey in the UI;
  /// other non-citizen staff map to officer.
  static Future<StaffLoginResult> staffLogin(
    String staffId,
    String password,
  ) async {
    final body = await _post('/login', {
      'username': staffId,
      'password': password,
    });
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    final role = (user['role'] as String? ?? 'department_officer')
        .toLowerCase();
    return StaffLoginResult(
      token: body['token'] as String? ?? '',
      id: user['id']?.toString() ?? '',
      staffId:
          user['username'] as String? ??
          user['employee_id'] as String? ??
          staffId,
      role: role,
      name: user['name'] as String?,
      officerProfileId: user['id']?.toString(),
    );
  }

  static Future<UserProfile> getProfile() async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw AuthApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(
            _uri('/me'),
            headers: {'Authorization': 'Bearer ${session.token}'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw AuthApiException(
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
      throw AuthApiException(
        body['message'] as String? ??
            'प्रोफ़ाइल लोड नहीं हो पाई। पुनः प्रयास करें।',
      );
    }

    final user = body['user'] as Map<String, dynamic>? ?? const {};
    return UserProfile.fromJson(user);
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            _uri(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw AuthApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        body['message'] as String? ?? 'कुछ गलत हो गया। पुनः प्रयास करें।',
      );
    }

    return body;
  }
}
