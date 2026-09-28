import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_role.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.role,
    this.serverRole,
    this.officerId,
    this.officerName,
    this.staffId,
    this.officerProfileId,
    this.assignedPanchayatId,
    this.assignedPanchayatName,
    this.assignedDistrictName,
  });

  final String token;
  final UserRole role;

  /// Raw backend role (`cplo`, `surveyor`, …). [role] is only the UI shell.
  final String? serverRole;

  /// Server-side user id, for display/UX only — the backend never trusts
  /// this value from the client, it always derives identity from the JWT.
  final String? officerId;
  final String? officerName;
  final String? staffId;

  /// The Officer table's own id — required for complaint assignment
  /// (self-accept, reassignment); distinct from [officerId] (the login
  /// User's id). Null for non-OFFICER staff (e.g. SURVEYOR).
  final String? officerProfileId;

  /// Set only for a Surveyor acting as CPLO (admin-assigned a single
  /// panchayat via the CPLO Management tab). Null for every other staff
  /// account, including surveyors with no panchayat assigned — those aren't
  /// scoped to any one area.
  final int? assignedPanchayatId;
  final String? assignedPanchayatName;

  /// The assigned panchayat's own district - authoritative for the survey
  /// form's District field, since the phone's on-device reverse-geocoder
  /// often reports the Division name instead (see AssetSurveyFormScreen).
  final String? assignedDistrictName;

  bool get isValid => token.isNotEmpty;
}

class AuthService {
  AuthService._();

  static const _tokenKey = 'auth_token';
  static const _roleKey = 'user_role';
  static const _serverRoleKey = 'server_role';
  static const _loggedInKey = 'is_logged_in';
  static const _officerIdKey = 'officer_id';
  static const _officerNameKey = 'officer_name';
  static const _staffIdKey = 'staff_id';
  static const _officerProfileIdKey = 'officer_profile_id';
  static const _assignedPanchayatIdKey = 'assigned_panchayat_id';
  static const _assignedPanchayatNameKey = 'assigned_panchayat_name';
  static const _assignedDistrictNameKey = 'assigned_district_name';

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
      serverRole: prefs.getString(_serverRoleKey),
      officerId: prefs.getString(_officerIdKey),
      officerName: prefs.getString(_officerNameKey),
      staffId: prefs.getString(_staffIdKey),
      officerProfileId: prefs.getString(_officerProfileIdKey),
      assignedPanchayatId: prefs.getInt(_assignedPanchayatIdKey),
      assignedPanchayatName: prefs.getString(_assignedPanchayatNameKey),
      assignedDistrictName: prefs.getString(_assignedDistrictNameKey),
    );
  }

  static Future<bool> isLoggedIn() async {
    final session = await getSession();
    return session?.isValid ?? false;
  }

  static Future<void> saveLogin({
    required UserRole role,
    required String token,
    String? serverRole,
    String? officerId,
    String? officerName,
    String? staffId,
    String? officerProfileId,
    int? assignedPanchayatId,
    String? assignedPanchayatName,
    String? assignedDistrictName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_roleKey, role.storageValue);
    await persistServerRole(serverRole);

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

    if (assignedPanchayatId != null) {
      await prefs.setInt(_assignedPanchayatIdKey, assignedPanchayatId);
    } else {
      await prefs.remove(_assignedPanchayatIdKey);
    }

    if (assignedPanchayatName != null) {
      await prefs.setString(_assignedPanchayatNameKey, assignedPanchayatName);
    } else {
      await prefs.remove(_assignedPanchayatNameKey);
    }

    if (assignedDistrictName != null) {
      await prefs.setString(_assignedDistrictNameKey, assignedDistrictName);
    } else {
      await prefs.remove(_assignedDistrictNameKey);
    }
  }

  static Future<void> persistAssignedPanchayat({
    int? id,
    String? name,
    String? districtName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setInt(_assignedPanchayatIdKey, id);
    }
    final value = name?.trim();
    if (value != null && value.isNotEmpty) {
      await prefs.setString(_assignedPanchayatNameKey, value);
    }
    final district = districtName?.trim();
    if (district != null && district.isNotEmpty) {
      await prefs.setString(_assignedDistrictNameKey, district);
    }
  }

  static Future<void> persistServerRole(String? serverRole) async {
    final prefs = await SharedPreferences.getInstance();
    final value = serverRole?.trim();
    if (value == null || value.isEmpty) {
      await prefs.remove(_serverRoleKey);
    } else {
      await prefs.setString(_serverRoleKey, value);
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_serverRoleKey);
    await prefs.remove(_officerIdKey);
    await prefs.remove(_officerNameKey);
    await prefs.remove(_staffIdKey);
    await prefs.remove(_officerProfileIdKey);
    await prefs.remove(_assignedPanchayatIdKey);
    await prefs.remove(_assignedPanchayatNameKey);
    await prefs.remove(_assignedDistrictNameKey);
  }
}
