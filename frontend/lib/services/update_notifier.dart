import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_version_service.dart';

/// Runs in its own isolate when a data message arrives while the app is in the
/// background or closed, so it must be a top-level function.
@pragma('vm:entry-point')
Future<void> updatePushBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }
  await UpdateNotifier.handle(message.data);
}

@pragma('vm:entry-point')
void updateNotificationTapBackground(NotificationResponse response) {
  unawaited(AppVersionService.openStore(response.payload));
}

/// "A newer version is out" push. The admin panel's Save sends a data-only FCM
/// message to a topic every install subscribes to; each phone compares the
/// announced build number with its own and only shows a notification when it is
/// actually out of date, so people who already updated are never nagged.
///
/// Best-effort like the rest of push: without Firebase config nothing happens,
/// and the launch-time version check / sign-in 426 keep working regardless.
class UpdateNotifier {
  UpdateNotifier._();

  static String get topic => 'app_update_${AppVersionService.platform}';
  static const _notificationId = 1001;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;
  static bool _started = false;

  /// Call once at app start (not awaited by the UI).
  static Future<void> start() async {
    if (kIsWeb || _started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(updatePushBackgroundHandler);
      await _initPlugin();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(); // Android 13+ runtime prompt
      await messaging.subscribeToTopic(topic);

      FirebaseMessaging.onMessage.listen((message) => handle(message.data));
    } catch (e) {
      // No / invalid Firebase config, offline, or permission refused.
      debugPrint('Update push disabled: $e');
    }
  }

  static Future<void> _initPlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested once by FirebaseMessaging.requestPermission().
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          unawaited(AppVersionService.openStore(response.payload)),
      onDidReceiveBackgroundNotificationResponse: updateNotificationTapBackground,
    );
    _pluginReady = true;
  }

  /// Shows the update notification if (and only if) this build is older than
  /// the announced latest one.
  static Future<void> handle(Map<String, dynamic> data) async {
    if (data['type'] != 'app_update') return;

    final current = int.tryParse(await AppVersionService.buildNumber()) ?? 0;
    final latest = int.tryParse('${data['latest_code'] ?? ''}') ?? 0;
    if (current >= latest) return;

    await _initPlugin();
    await _plugin.show(
      id: _notificationId,
      title: 'म्हारी पंचायत – अपडेट उपलब्ध',
      body: (data['message'] as String?) ?? 'नया वर्ज़न उपलब्ध है, कृपया ऐप अपडेट करें।',
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          'app_update',
          'App Updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: data['store_url'] as String?,
    );
  }
}
