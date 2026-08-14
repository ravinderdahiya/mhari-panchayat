import 'package:flutter/services.dart';

/// Bridges to the native Android check for Developer Options
/// (Settings.Global.DEVELOPMENT_SETTINGS_ENABLED) - Flutter has no direct
/// API for this, so it goes through a MethodChannel to MainActivity.
class DeviceSecurityService {
  DeviceSecurityService._();

  static const _channel = MethodChannel('mhari_panchayat/device_security');

  /// Defaults to false (assume safe) on platforms without this channel,
  /// e.g. iOS/web, which have no equivalent developer-options toggle.
  static Future<bool> isDeveloperModeEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('isDeveloperModeEnabled');
      return enabled ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
