import 'package:flutter/foundation.dart';

import '../services/app_preferences.dart';

/// Single global source of truth for dark mode. Plain `ValueNotifier`
/// (this app has no DI/state-management framework) so both `app.dart`
/// (to pick MaterialApp's themeMode) and `AppColors`' dynamic getters (no
/// BuildContext available there) can read the same value.
class ThemeController extends ValueNotifier<bool> {
  ThemeController._() : super(false);

  static final ThemeController instance = ThemeController._();

  /// Loads the persisted choice at startup, before the first frame -
  /// `AppColors` getters already default to light (matches the initial
  /// `false`) so there's no flash of the wrong theme while this resolves.
  ///
  /// Dark mode is no longer offered in Settings, so the app is always light:
  /// anyone who switched it on in an earlier version is reset here rather than
  /// being stuck in a theme they can no longer turn off.
  static Future<void> load() async {
    instance.value = false;
    if (await AppPreferences.getDarkMode()) {
      await AppPreferences.setDarkMode(false);
    }
  }

  Future<void> setDark(bool value) async {
    if (value == this.value) return;
    this.value = value;
    await AppPreferences.setDarkMode(value);
  }
}
