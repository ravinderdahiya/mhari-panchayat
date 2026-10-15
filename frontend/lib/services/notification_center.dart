import 'dart:async';

import 'package:flutter/foundation.dart';

import 'notification_api.dart';
import 'push_service.dart';

/// Keeps the unread-notification count fresh for the badges on the bottom
/// navigation. Shells call [start] / [stop] (reference counted, so nested or
/// swapped shells never leave two timers running); the notifications screen
/// pushes exact numbers in through [setUnread] as it loads and marks things read.
class NotificationCenter {
  NotificationCenter._();

  static final instance = NotificationCenter._();

  static const _interval = Duration(seconds: 60);

  final unread = ValueNotifier<int>(0);
  Timer? _timer;
  int _users = 0;

  void start() {
    _users++;
    unawaited(refresh());
    // Every signed-in shell starts this, so it doubles as the push registration point.
    unawaited(PushService.instance.ensureStarted());
    _timer ??= Timer.periodic(_interval, (_) => refresh());
  }

  void stop() {
    _users = _users > 0 ? _users - 1 : 0;
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> refresh() async {
    try {
      unread.value = await NotificationApi.unreadCount();
    } catch (_) {
      // Offline or logged out - keep showing the last known count.
    }
  }

  void setUnread(int count) => unread.value = count < 0 ? 0 : count;
}
