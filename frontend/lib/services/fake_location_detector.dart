import 'package:detect_fake_location/detect_fake_location.dart';

/// Wraps detect_fake_location so GPS-capture call sites don't each import
/// the plugin directly, and so a plugin failure (unsupported platform,
/// missing permission) never blocks a real capture - it just reports
/// "not fake" and lets the existing flow continue.
class FakeLocationDetector {
  FakeLocationDetector._();

  static Future<bool> isFakeLocation() async {
    try {
      return await DetectFakeLocation().detectFakeLocation();
    } catch (_) {
      return false;
    }
  }
}
