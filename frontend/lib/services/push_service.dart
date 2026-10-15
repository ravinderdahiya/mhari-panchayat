import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_api.dart';
import 'notification_center.dart';

/// Push notifications (FCM) for when the app is closed or in the background.
///
/// Everything here is best-effort: without `android/app/google-services.json`
/// Firebase can't start, [ensureStarted] quietly does nothing, and the app keeps
/// using only the in-app Alerts inbox. While the app is open the system shows no
/// banner, so a message just refreshes the unread badge.
class PushService {
  PushService._();

  static final instance = PushService._();

  bool _firebaseReady = false;
  bool _firebaseFailed = false;
  bool _listening = false;
  String? _token;

  /// Call whenever a user is signed in (idempotent). Re-registers the token each
  /// time so a phone that switches accounts pushes to the new user only.
  Future<void> ensureStarted() async {
    if (kIsWeb || _firebaseFailed) return;
    if (!_firebaseReady) {
      try {
        await Firebase.initializeApp();
        _firebaseReady = true;
      } catch (_) {
        // No / invalid Firebase config: push is simply unavailable on this build.
        _firebaseFailed = true;
        return;
      }
    }
    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ asks at runtime; earlier versions grant it implicitly.
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token == null) return;
      _token = token;
      await NotificationApi.registerDevice(token);

      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((fresh) async {
          _token = fresh;
          try {
            await NotificationApi.registerDevice(fresh);
          } catch (_) {
            // Registered again on the next launch.
          }
        });
        FirebaseMessaging.onMessage.listen((_) => NotificationCenter.instance.refresh());
      }
    } on Exception catch (e) {
      // Offline, or the server rejected the token - retried on the next start.
      debugPrint('Push setup skipped: $e');
    }
  }

  /// Detaches this phone from the signed-in user. Call before clearing the session.
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await NotificationApi.unregisterDevice(token);
    } catch (_) {
      // Best effort: the server also drops tokens FCM reports as dead.
    }
  }
}
