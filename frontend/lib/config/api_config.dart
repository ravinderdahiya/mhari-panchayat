import 'package:flutter/foundation.dart';

/// Base URL for the Mhari Panchayat Laravel backend.
class ApiConfig {
  ApiConfig._();

  /// Override anytime:
  /// `flutter run --dart-define=API_BASE_URL=https://hsac.in/mhari-panchayat`
  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');


  /// Phone + PC same Wi‑Fi / hotspot. Change this IP if your LAN address
  /// changes - check with `ipconfig` on the PC side.
  static const String localBaseUrl = 'http://192.168.137.1:8083';

  /// Phone + PC same Wi‑Fi. Change this IP if your LAN address changes.
  // static const String localBaseUrl = 'http://172.16.1.190:8083';


  static const String liveBaseUrl = 'https://hsac.in/mhari-panchayat';

  /// Debug/profile → local backend. Release → live.
  /// Pass `--dart-define=API_BASE_URL=...` to override either way.
  static String get baseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    if (kReleaseMode) return liveBaseUrl;
    return localBaseUrl;
  }

  /// Alias retained for registration API call sites.
  static String get mhariPanchayatBaseUrl => baseUrl;

  /// Boundary overlay uses the same proxy as the live admin dashboard.
  /// Local Laravel cannot mint a GIS token from this LAN (`gis.harsac.in`
  /// times out), which is why the layer vanished after pointing at `:8083`.
  static String get gisPanchayatMapServerUrl =>
      '$liveBaseUrl/api/gis/panchayat';
}
