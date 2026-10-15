import 'package:flutter/material.dart';

import '../services/notification_center.dart';
import '../widgets/location_gate.dart';
import '../widgets/notification_badge.dart';
import 'asset_survey_screen.dart';
import 'complaint_map_screen.dart';
import 'notification_screen.dart';
import 'surveyor_profile_screen.dart';

/// CPLO handles field asset surveys only, never complaints - Home is the
/// survey form, Map is the asset-survey map with complaints switched off
/// entirely (no complaint markers, legend, or status filter), Alerts tells them
/// when a survey was returned / rejected / approved, and there is deliberately
/// no Tasks/complaint-queue tab.
class CploShell extends StatefulWidget {
  const CploShell({super.key});

  @override
  State<CploShell> createState() => _CploShellState();
}

class _CploShellState extends State<CploShell> {
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
      const AssetSurveyScreen(embedded: true),
      const LocationGate(
        child: ComplaintMapScreen(staffQueue: true, showComplaints: false),
      ),
      // Rebuilt on every visit so the list is fresh; the other tabs keep their state.
      _index == 2
          ? const NotificationScreen(showBackButton: false)
          : const SizedBox.shrink(),
      const SurveyorProfileScreen(embedded: true),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
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
