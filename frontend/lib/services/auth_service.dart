import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_role.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.role,
    this.officerId,
    this.officerName,
    this.staffId,
    this.officerProfileId,
  });

  final String token;
  final UserRole role;

  /// Server-side user id, for display/UX only — the backend never trusts
  /// this value from the client, it always derives identity from the JWT.
  final String? officerId;
  final String? officerName;
  final String? staffId;

  /// The Officer table's own id — required for complaint assignment
  /// (self-accept, reassignment); distinct from [officerId] (the login
  /// User's id). Null for non-OFFICER staff (e.g. SURVEYOR).
  final String? officerProfileId;

  bool get isValid => token.isNotEmpty;
}

class AuthService {
  AuthService._();

  static const _tokenKey = 'auth_token';
  static const _roleKey = 'user_role';
  static const _loggedInKey = 'is_logged_in';
  static const _officerIdKey = 'officer_id';
  static const _officerNameKey = 'officer_name';
  static const _staffIdKey = 'staff_id';
  static const _officerProfileIdKey = 'officer_profile_id';

  static Future<AuthSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_loggedInKey) ?? false;
    final token = prefs.getString(_tokenKey);
    final role = UserRoleStorage.fromStorage(prefs.getString(_roleKey));

    if (!isLoggedIn || token == null || token.isEmpty || role == null) {
      return null;
    }

    return AuthSession(
      token: token,
      role: role,
      officerId: prefs.getString(_officerIdKey),
      officerName: prefs.getString(_officerNameKey),
      staffId: prefs.getString(_staffIdKey),
      officerProfileId: prefs.getString(_officerProfileIdKey),
    );
  }

  static Future<bool> isLoggedIn() async {
    final session = await getSession();
    return session?.isValid ?? false;
  }

  static Future<void> saveLogin({
    required UserRole role,
    required String token,
    String? officerId,
    String? officerName,
    String? staffId,
    String? officerProfileId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_roleKey, role.storageValue);

    if (officerId != null) {
      await prefs.setString(_officerIdKey, officerId);
    } else {
      await prefs.remove(_officerIdKey);
    }

    if (officerName != null) {
      await prefs.setString(_officerNameKey, officerName);
    } else {
      await prefs.remove(_officerNameKey);
    }

    if (staffId != null) {
      await prefs.setString(_staffIdKey, staffId);
    } else {
      await prefs.remove(_staffIdKey);
    }

    if (officerProfileId != null) {
      await prefs.setString(_officerProfileIdKey, officerProfileId);
    } else {
      await prefs.remove(_officerProfileIdKey);
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_officerIdKey);
    await prefs.remove(_officerNameKey);
    await prefs.remove(_staffIdKey);
    await prefs.remove(_officerProfileIdKey);
  }
}
