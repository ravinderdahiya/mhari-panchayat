import 'package:flutter/material.dart';

import '../navigation/navigator_key.dart';
import '../screens/login_screen.dart';
import 'auth_service.dart';

/// Reacts to a 401 from any API call by clearing the stored session and
/// sending the user back to the login screen, instead of leaving screens to
/// show the raw "Invalid or expired token" backend message inline.
class SessionGuard {
  SessionGuard._();

  static bool _handling = false;

  static Future<void> handleUnauthorized() async {
    if (_handling) return;
    _handling = true;
    try {
      await AuthService.logout();
      final navigator = rootNavigatorKey.currentState;
      navigator?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } finally {
      _handling = false;
    }
  }
}
