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
  static Future<void> load() async {
    instance.value = await AppPreferences.getDarkMode();
  }

  Future<void> setDark(bool value) async {
    if (value == this.value) return;
    this.value = value;
    await AppPreferences.setDarkMode(value);
  }
}
