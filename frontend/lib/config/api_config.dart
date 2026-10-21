import 'package:flutter/foundation.dart';

/// Base URL for the Mhari Panchayat Laravel backend.
class ApiConfig {
  ApiConfig._();

  /// Override anytime:
  /// `flutter run --dart-define=API_BASE_URL=https://hsac.in/mhari-panchayat`
  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');


  /// Phone + PC same Wi‑Fi / hotspot. Change this IP if your LAN address
  /// changes - check with `ipconfig` on the PC side.
  // static const String localBaseUrl = 'http://192.168.137.1:8083';

  /// Phone + PC same Wi‑Fi. Change this IP if your LAN address changes.
  static const String localBaseUrl = 'http://172.16.1.174:8083';


  static const String liveBaseUrl = 'https://hsac.in/mhari-panchayat';

  /// true → debug/profile builds also hit the live backend.
  /// Set to false to test against the local Laravel server (localBaseUrl).
  static const bool useLiveBackend = true;

  /// Release → always live. Debug/profile → live unless useLiveBackend is off.
  /// Pass `--dart-define=API_BASE_URL=...` to override either way.
  static String get baseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    if (kReleaseMode || useLiveBackend) return liveBaseUrl;
    return localBaseUrl;
  }

  /// Alias retained for registration API call sites.
  static String get mhariPanchayatBaseUrl => baseUrl;

  /// Re-points a stored media URL (profile photo, ...) at the API host in use.
  /// The backend builds absolute URLs from its own APP_URL, which can differ from
  /// the address the app reaches it on (emulator, LAN, a sub-path deployment).
  static String mediaUrl(String value) {
    final base = Uri.parse(baseUrl);
    final basePath = base.path.isEmpty || base.path == '/' ? '' : base.path;

    final parsed = Uri.tryParse(value);
    var path = parsed != null && parsed.hasScheme
        ? (parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path)
        : (value.startsWith('/') ? value : '/$value');

    if (basePath.isNotEmpty && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }

    return '${base.scheme}://${base.authority}$basePath$path';
  }

  /// Served as a static file from the Laravel backend's public/ dir -
  /// see backend/public/privacy-policy.html.
  static String get privacyPolicyUrl => '$baseUrl/privacy-policy.html';

  /// Terms of Service page served from `backend/public/terms-of-service.html`.
  static String get termsOfServiceUrl => '$baseUrl/terms-of-service.html';

  /// Boundary overlay uses the same proxy as the live admin dashboard.
  /// Local Laravel cannot mint a GIS token from this LAN (`gis.harsac.in`
  /// times out), which is why the layer vanished after pointing at `:8083`.
  static String get gisPanchayatMapServerUrl =>
      '$liveBaseUrl/api/gis/panchayat';
}
