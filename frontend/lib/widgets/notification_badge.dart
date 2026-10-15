import 'package:flutter/material.dart';

import '../services/notification_center.dart';

/// A notifications bell with the unread count as a badge, for bottom navigation.
class NotificationBadgeIcon extends StatelessWidget {
  const NotificationBadgeIcon({super.key, required this.icon, this.size = 24});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationCenter.instance.unread,
      builder: (context, count, _) => Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(icon, size: size),
      ),
    );
  }
}
