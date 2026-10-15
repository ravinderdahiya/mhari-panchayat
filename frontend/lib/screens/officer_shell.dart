import 'package:flutter/material.dart';

import '../services/notification_center.dart';
import '../widgets/adaptive_nav_scaffold.dart';
import '../widgets/location_gate.dart';
import '../widgets/notification_badge.dart';
import 'complaint_map_screen.dart';
import 'notification_screen.dart';
import 'officer_dashboard_screen.dart';
import 'officer_tasks_screen.dart';
import 'profile_screen.dart';

class OfficerShell extends StatefulWidget {
  const OfficerShell({super.key});

  @override
  State<OfficerShell> createState() => _OfficerShellState();
}

class _OfficerShellState extends State<OfficerShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    NotificationCenter.instance.start();
  }

  @override
  void dispose() {
    NotificationCenter.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      OfficerDashboardScreen(onProfileTap: () => setState(() => _index = 4)),
      const LocationGate(child: ComplaintMapScreen(staffQueue: true)),
      const OfficerTasksScreen(),
      const NotificationScreen(showBackButton: false),
      const ProfileScreen(showReportsLink: true),
    ];

    return AdaptiveNavScaffold(
      body: screens[_index],
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined, size: 24),
          selectedIcon: Icon(Icons.home_rounded, size: 24),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined, size: 24),
          selectedIcon: Icon(Icons.map_rounded, size: 24),
          label: 'Map',
        ),
        NavigationDestination(
          icon: Icon(Icons.task_outlined, size: 24),
          selectedIcon: Icon(Icons.task_rounded, size: 24),
          label: 'Tasks',
        ),
        NavigationDestination(
          icon: NotificationBadgeIcon(icon: Icons.notifications_outlined),
          selectedIcon: NotificationBadgeIcon(icon: Icons.notifications_rounded),
          label: 'Alerts',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline, size: 24),
          selectedIcon: Icon(Icons.person_rounded, size: 24),
          label: 'Profile',
        ),
      ],
    );
  }
}
