import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../navigation/navigator_key.dart';
import '../screens/set_password_screen.dart';
import 'registration_api.dart';

final splashNavigationDone = ValueNotifier<bool>(false);

/// Handles basmati-style registration deep links:
/// - `mharipanchayat://verify-email?token=…`
/// - `mharipanchayat://set-password?token=…&email=…`
/// - HTTPS `…/registrations/email/verify-link?token=…`
class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;
  bool _handling = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handle(initial));
      }
    } catch (_) {}

    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  Future<void> _handle(Uri uri) async {
    if (_handling) return;
    final path = '${uri.host}${uri.path}'.toLowerCase();
    final token = uri.queryParameters['token']?.trim() ?? '';
    if (token.isEmpty) return;

    final isSetPassword =
        uri.host == 'set-password' || path.contains('set-password');
    final isVerifyEmail =
        uri.host == 'verify-email' ||
        path.contains('verify-email') ||
        path.contains('verify-link');
    if (!isSetPassword && !isVerifyEmail) return;

    _handling = true;
    try {
      for (var i = 0; i < 10 && rootNavigatorKey.currentContext == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      var setupToken = token;
      var email = uri.queryParameters['email']?.trim();

      if (isVerifyEmail) {
        final result = await RegistrationApi.completeEmailVerification(token);
        setupToken = result.passwordSetupToken;
        email = result.email ?? email;
        if (setupToken.isEmpty) return;
      }

      await _openSetPassword(setupToken, email: email);
    } catch (e) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              e is RegistrationApiException
                  ? e.message
                  : 'Could not open set-password link',
            ),
          ),
        );
      }
    } finally {
      _handling = false;
    }
  }

  Future<void> _openSetPassword(String token, {String? email}) async {
    void push() {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SetPasswordScreen(initialToken: token, accountEmail: email),
        ),
      );
    }

    if (splashNavigationDone.value) {
      push();
      return;
    }

    final done = Completer<void>();
    late final VoidCallback listener;
    listener = () {
      if (!splashNavigationDone.value) return;
      splashNavigationDone.removeListener(listener);
      if (!done.isCompleted) done.complete();
    };
    splashNavigationDone.addListener(listener);
    await done.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    splashNavigationDone.removeListener(listener);
    push();
  }
}

// Kept so older registration_screen references compile during transition.
class PendingRegistrationLink {
  PendingRegistrationLink(this.email, this.token);
  final String email;
  final String token;
}

final pendingRegistrationLink = ValueNotifier<PendingRegistrationLink?>(null);
