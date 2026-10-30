import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'citizen_location_sync.dart';
import 'notification_api.dart';
import 'push_service.dart';

/// Keeps the unread-notification count fresh for the badges on the bottom
/// navigation. Shells call [start] / [stop] (reference counted, so nested or
/// swapped shells never leave two timers running); the notifications screen
/// pushes exact numbers in through [setUnread] as it loads and marks things read.
class NotificationCenter {
  NotificationCenter._();

  static final instance = NotificationCenter._();

  // Every signed-in phone polls the unread count. A fixed minute made 10,000 users ~170 requests/second on
  // their own, so it is 2-3 minutes with a random gap (push notifications already cover urgent news).
  static const _baseSeconds = 150;
  static const _jitterSeconds = 30;

  /// The wait before the next poll: 150 s +/- 30 s, so phones never poll in lockstep.
  static Duration pollDelay([Random? random]) =>
      Duration(seconds: _baseSeconds - _jitterSeconds + (random ?? Random()).nextInt(2 * _jitterSeconds + 1));

  final unread = ValueNotifier<int>(0);
  Timer? _timer;
  int _users = 0;

  void start() {
    _users++;
    unawaited(refresh());
    // Every signed-in shell starts this, so it doubles as the push registration point.
    unawaited(PushService.instance.ensureStarted());
    unawaited(CitizenLocationSync.run());
    if (_timer == null) _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    _timer = Timer(pollDelay(), () async {
      await refresh();
      if (_timer != null) _scheduleNextPoll();
    });
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
