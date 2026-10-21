import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';

enum UpdateStatus { ok, optional, force }

class AppVersionCheck {
  const AppVersionCheck({
    required this.status,
    this.message,
    this.storeUrl,
  });

  static const ok = AppVersionCheck(status: UpdateStatus.ok);

  final UpdateStatus status;
  final String? message;
  final String? storeUrl;
}

/// Launch-time "is this build still allowed?" check against the backend
/// (`POST /api/app/version-check`). The comparison is on the integer build
/// number (the `+N` in pubspec `version:`), never the version name.
class AppVersionService {
  AppVersionService._();

  static String? _buildNumber;
  static String? _versionName;
  static String? _packageName;

  /// Header every sign-in call carries so the server can refuse outdated builds.
  static const headerName = 'X-App-Version-Code';
  static const platformHeaderName = 'X-App-Platform';

  /// 'ios' or 'android' - the release channel this build belongs to.
  static String get platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  static Future<PackageInfo> _info() => PackageInfo.fromPlatform();

  static Future<String> buildNumber() async {
    final cached = _buildNumber;
    if (cached != null) return cached;
    try {
      final info = await _info();
      _packageName = info.packageName;
      _versionName = info.version;
      return _buildNumber = info.buildNumber;
    } catch (_) {
      return '0';
    }
  }

  /// Installed version for display, e.g. "1.0.1 (2)" - read from the build,
  /// so it always matches pubspec `version:` and the Play Store listing.
  /// Empty if the platform can't report it.
  static Future<String> displayVersion() async {
    final build = await buildNumber();
    final name = _versionName;
    if (name == null || name.isEmpty) return '';
    return '$name ($build)';
  }

  /// Never blocks the user on a failed check: offline, server errors and
  /// unparsable answers all count as "ok" (the server still enforces the
  /// minimum on sign-in).
  static Future<AppVersionCheck> check() async {
    try {
      final code = await buildNumber();
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/app/version-check'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'version_code': int.tryParse(code) ?? 0, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return AppVersionCheck.ok;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = switch (body['status']) {
        'force_update' => UpdateStatus.force,
        'optional_update' => UpdateStatus.optional,
        _ => UpdateStatus.ok,
      };

      return AppVersionCheck(
        status: status,
        message: body['message'] as String?,
        storeUrl: body['store_url'] as String?,
      );
    } catch (_) {
      return AppVersionCheck.ok;
    }
  }

  /// Opens the Play Store listing in the Play Store app, falling back to the
  /// web URL the backend sent.
  static Future<void> openStore(String? fallbackUrl) async {
    // iOS has no market:// scheme: the App Store link from the backend is used as is.
    if (platform == 'ios') {
      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
      }
      return;
    }

    await buildNumber(); // makes sure the package name is loaded
    final package = _packageName;
    if (package != null) {
      final market = Uri.parse('market://details?id=$package');
      try {
        if (await launchUrl(market, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // No Play Store app - use the web URL below.
      }
    }
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }
}
