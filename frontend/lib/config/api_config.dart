/// Base URL for the Mhari Panchayat Laravel backend.
class ApiConfig {
  ApiConfig._();

  /// Override at build/run time when a development backend is required:
  /// `--dart-define=API_BASE_URL=http://127.0.0.1:8081`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hsac.in/mhari-panchayat',
  );

  /// Alias retained for registration API call sites.
  static const String mhariPanchayatBaseUrl = baseUrl;
}
