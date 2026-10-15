import 'package:flutter/material.dart';

import '../services/notification_center.dart';
import '../widgets/notification_badge.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'survey_verification_screen.dart';

class GramSachivShell extends StatefulWidget {
  const GramSachivShell({super.key});

  @override
  State<GramSachivShell> createState() => _GramSachivShellState();
}

class _GramSachivShellState extends State<GramSachivShell> {
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
    final screen = switch (_index) {
      0 => const SurveyVerificationScreen(),
      1 => const NotificationScreen(showBackButton: false),
      _ => const ProfileScreen(),
    };

    return Scaffold(
      body: screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined, size: 24),
            selectedIcon: Icon(Icons.fact_check_rounded, size: 24),
            label: 'Verify',
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
      ),
    );
  }
}
