import 'package:shared_preferences/shared_preferences.dart';

/// User-facing app preferences that aren't tied to a login session (dark
/// mode, language) - kept separate from [AuthService] since these persist
/// across logout/login, unlike the auth keys there.
class AppPreferences {
  AppPreferences._();

  static const _darkModeKey = 'pref_dark_mode';
  static const _englishKey = 'pref_language_en';

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  /// True for English, false for Hindi (Hindi is this app's default).
  static Future<bool> getIsEnglish() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_englishKey) ?? false;
  }

  static Future<void> setIsEnglish(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_englishKey, value);
  }
}
