import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class RegistrationApiException implements Exception {
  RegistrationApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RegistrationDistrict {
  const RegistrationDistrict({required this.id, required this.name});

  final int id;
  final String name;

  factory RegistrationDistrict.fromJson(Map<String, dynamic> json) =>
      RegistrationDistrict(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
      );
}

class RegistrationStartResult {
  const RegistrationStartResult({
    required this.userId,
    required this.message,
    this.devEmailToken = '',
  });

  final int userId;
  final String message;
  final String devEmailToken;
}

class RegistrationOtpResult {
  const RegistrationOtpResult({
    required this.message,
    required this.smsSent,
    this.devOtp = '',
  });

  final String message;
  final bool smsSent;
  final String devOtp;
}

class RegistrationStatusResult {
  const RegistrationStatusResult({
    required this.status,
    required this.role,
    this.rejectionReason,
  });

  final String status;
  final String role;
  final String? rejectionReason;
}

class EmailVerifyResult {
  const EmailVerifyResult({required this.passwordSetupToken, this.email});

  final String passwordSetupToken;
  final String? email;
}

/// mhari-panchayat registration API — basmati-survey-app lifecycle:
/// phone OTP → self-register (pending_email) → email verify → set password →
/// pending_review → admin approve.
class RegistrationApi {
  RegistrationApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.mhariPanchayatBaseUrl}/api$path');

  static Future<List<RegistrationDistrict>> getDistricts() async {
    final body = await _get('/registrations/districts');
    final list = body['districts'] as List<dynamic>? ?? [];
    return list
        .map((e) => RegistrationDistrict.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<RegistrationOtpResult> sendPhoneOtp(String mobile) async {
    final body = await _post('/registrations/phone/send-otp', {
      'mobile': mobile,
    });
    return RegistrationOtpResult(
      message: body['message'] as String? ?? 'OTP request completed',
      smsSent: body['smsSent'] as bool? ?? body['sms_sent'] as bool? ?? false,
      devOtp: body['devOtp'] as String? ?? '',
    );
  }

  static Future<String> verifyPhoneOtp({
    required String mobile,
    required String otp,
  }) async {
    final body = await _post('/registrations/phone/verify-otp', {
      'mobile': mobile,
      'otp': otp,
    });
    return body['phone_token'] as String? ?? '';
  }

  /// Resend verification email for an existing pending_email registration.
  static Future<String> resendVerificationEmail(String email) async {
    final body = await _post('/registrations/email/send-link', {
      'email': email,
    });
    return body['devEmailToken'] as String? ?? '';
  }

  /// Completes email verification from an in-app deep link (basmati-style).
  static Future<EmailVerifyResult> completeEmailVerification(
    String emailToken,
  ) async {
    final uri = _uri(
      '/registrations/email/verify-link',
    ).replace(queryParameters: {'token': emailToken, 'format': 'json'});
    late final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: const {'Accept': 'application/json', 'X-Mhari-App': '1'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw RegistrationApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    final body = _decode(response);
    return EmailVerifyResult(
      passwordSetupToken: body['passwordSetupToken'] as String? ?? '',
      email: body['email'] as String?,
    );
  }

  static Future<String> setPassword({
    required String token,
    required String password,
    required String confirmPassword,
  }) async {
    final body = await _post('/registrations/set-password', {
      'token': token,
      'password': password,
      'password_confirmation': confirmPassword,
    });
    return body['message'] as String? ?? 'Password saved.';
  }

  static Future<RegistrationStartResult> registerSurveyor({
    required String name,
    required String mobile,
    required String phoneToken,
    required String email,
    required int districtId,
  }) {
    return _post('/registrations/surveyor', {
      'name': name,
      'mobile': mobile,
      'phone_token': phoneToken,
      'email': email,
      'district_id': districtId,
    }).then(_startResult);
  }

  static Future<RegistrationStartResult> registerOfficer({
    required String name,
    required String mobile,
    required String phoneToken,
    required String email,
    required int districtId,
    required String employeeId,
  }) {
    return _post('/registrations/officer', {
      'name': name,
      'mobile': mobile,
      'phone_token': phoneToken,
      'email': email,
      'district_id': districtId,
      'employee_id': employeeId,
    }).then(_startResult);
  }

  static RegistrationStartResult _startResult(Map<String, dynamic> body) {
    return RegistrationStartResult(
      userId: body['user_id'] as int? ?? 0,
      message: body['message'] as String? ?? '',
      devEmailToken: body['devEmailToken'] as String? ?? '',
    );
  }

  static Future<RegistrationStatusResult> getStatus(int userId) async {
    final body = await _get('/registrations/$userId/status');
    return RegistrationStatusResult(
      status: body['registration_status'] as String? ?? 'pending_review',
      role: body['role'] as String? ?? '',
      rejectionReason: body['rejection_reason'] as String?,
    );
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    late final http.Response response;
    try {
      response = await http
          .get(_uri(path), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw RegistrationApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    return _decode(response);
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
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw RegistrationApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }
    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = body['errors'] as Map<String, dynamic>?;
      final firstFieldError = errors != null && errors.isNotEmpty
          ? ((errors.values.first as List<dynamic>?)?.first as String?)
          : null;
      throw RegistrationApiException(
        firstFieldError ??
            body['message'] as String? ??
            'कुछ गलत हो गया। पुनः प्रयास करें।',
      );
    }

    return body;
  }
}
