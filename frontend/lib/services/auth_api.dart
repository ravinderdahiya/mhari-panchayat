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

class StaffResetOtpResult {
  const StaffResetOtpResult({
    required this.message,
    required this.smsSent,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
    this.mobileHint,
  });

  final String message;
  final bool smsSent;
  final int expiresInSeconds;
  final int resendAfterSeconds;
  final String? mobileHint;
}

class StaffLoginResult {
  const StaffLoginResult({
    required this.token,
    required this.id,
    required this.staffId,
    required this.role,
    this.name,
    this.officerProfileId,
    this.assignedPanchayatId,
    this.assignedPanchayatName,
  });

  final String token;
  final String id;
  final String staffId;
  final String role;
  final String? name;

  /// The Officer table's own id (distinct from the login User id) —
  /// null for non-OFFICER staff (e.g. SURVEYOR).
  final String? officerProfileId;

  /// Set only when this account has been given a single panchayat to act as
  /// CPLO (see CploManagementPage on the admin side).
  final int? assignedPanchayatId;
  final String? assignedPanchayatName;
}

class UserProfile {
  const UserProfile({
    required this.id,
    this.mobile,
    this.staffId,
    this.name,
    required this.role,
    this.email,
    this.departmentName,
    this.districtName,
    this.blockName,
    this.panchayatName,
    this.panchayatId,
    this.employeeId,
    this.memberId,
    this.familyId,
  });

  final String id;
  final String? mobile;
  final String? staffId;
  final String? name;
  final String role;
  final String? email;
  final String? departmentName;

  // Jurisdiction the account is scoped to, if any (district-level staff
  // carry only districtName; a CPLO/Gram Sachiv carries all three since
  // panchayat implies a block implies a district).
  final String? districtName;
  final String? blockName;
  final String? panchayatName;
  final int? panchayatId;
  final String? employeeId;
  final String? memberId;
  final String? familyId;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    String? asString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    String? relationName(String key) =>
        asString((json[key] as Map<String, dynamic>?)?['name']);

    int? relationId(String key) {
      final nested = json[key] as Map<String, dynamic>?;
      return int.tryParse(nested?['id']?.toString() ?? '') ??
          int.tryParse(json['${key}_id']?.toString() ?? '');
    }

    return UserProfile(
      id: json['id']?.toString() ?? '',
      mobile: asString(json['mobile']),
      staffId:
          asString(json['username']) ??
          asString(json['staffId']) ??
          asString(json['employee_id']),
      name: asString(json['name']),
      role: asString(json['role']) ?? 'citizen',
      email: asString(json['email']),
      departmentName: relationName('department'),
      districtName: relationName('district'),
      blockName: relationName('block'),
      panchayatName: relationName('panchayat'),
      panchayatId: relationId('panchayat'),
      employeeId: asString(json['employee_id']),
      memberId: asString(json['member_id']),
      familyId: asString(json['family_id']),
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
  /// (username + password). Surveyor/CPLO/engineer map to the asset-survey
  /// UI; gram sachiv to verification; other non-citizen staff to officer.
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
    final panchayat = user['panchayat'] as Map<String, dynamic>?;
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
      assignedPanchayatId: int.tryParse(panchayat?['id']?.toString() ?? ''),
      assignedPanchayatName: panchayat?['name'] as String?,
    );
  }

  /// Step 1 of staff "forgot password" - OTP goes to the mobile number on
  /// file for the account (mirrors `sendOtp` for citizens), not whatever the
  /// requester types, so the response never reveals whether [identifier]
  /// actually matched an account.
  static Future<StaffResetOtpResult> sendStaffPasswordResetOtp(
    String identifier,
  ) async {
    final body = await _post('/forgot-password/staff/send-otp', {
      'identifier': identifier,
    });
    return StaffResetOtpResult(
      message: body['message'] as String? ?? 'OTP भेजा गया है',
      smsSent: body['smsSent'] as bool? ?? false,
      expiresInSeconds: (body['expiresIn'] as num?)?.toInt() ?? 600,
      resendAfterSeconds: (body['resendAfter'] as num?)?.toInt() ?? 30,
      mobileHint: body['mobileHint'] as String?,
    );
  }

  /// Step 2: verify the OTP from [sendStaffPasswordResetOtp] and set the
  /// new password in one call.
  static Future<void> verifyStaffPasswordReset({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    await _post('/forgot-password/staff/verify-reset', {
      'identifier': identifier,
      'otp': otp,
      'new_password': newPassword,
      'new_password_confirmation': newPassword,
    });
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

  /// Backend role for field-app labels. Uses the value stored at login,
  /// and fills it from `/me` when an older session only has the UI shell.
  static Future<String?> resolvedFieldRole() async {
    final session = await AuthService.getSession();
    final stored = session?.serverRole?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    try {
      final profile = await getProfile();
      final role = profile.role.trim();
      if (role.isNotEmpty) {
        await AuthService.persistServerRole(role);
        return role;
      }
    } catch (_) {}
    return stored;
  }

  /// Self-service password change for the logged-in user (any role,
  /// including CPLO) — no admin action required.
  static Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw AuthApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _uri('/change-password'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.token}',
            },
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
              'new_password_confirmation': newPasswordConfirmation,
            }),
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
      final errors = body['errors'] as Map<String, dynamic>?;
      final firstFieldError = errors != null && errors.isNotEmpty
          ? ((errors.values.first as List<dynamic>?)?.first as String?)
          : null;
      throw AuthApiException(
        firstFieldError ??
            body['message'] as String? ??
            'पासवर्ड बदला नहीं जा सका। पुनः प्रयास करें।',
      );
    }

    return body['message'] as String? ?? 'Password changed successfully';
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
