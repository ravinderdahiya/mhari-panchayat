import 'package:flutter/material.dart';

import '../services/notification_center.dart';
import '../widgets/notification_badge.dart';
import 'complaint_map_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'survey_verification_screen.dart';

/// Shared shell for the four upper stages of the asset-survey verification
/// escalation chain - BDPO, DDPO, XEN-PR, CEO-ZP. Each sees the same
/// Verify/Map/Alerts/Profile tabs; [SurveyVerificationScreen] adapts its queue and
/// actions to whichever of the four is actually signed in, the Map shows only
/// the assets of that reviewer's own jurisdiction, and Alerts tells them when a
/// survey reaches their stage (the server scopes both, exactly like the queue).
class VerifierShell extends StatefulWidget {
  const VerifierShell({super.key});

  @override
  State<VerifierShell> createState() => _VerifierShellState();
}

class _VerifierShellState extends State<VerifierShell> {
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

  // No location gate here (unlike the CPLO map): reviewing surveys doesn't need
  // the phone's GPS, the map just won't show a "my location" dot without it.
  // Kept alive across tab switches so the camera and loaded assets survive;
  // Verify, Alerts and Profile are rebuilt on every visit so they stay fresh.
  final _map = const ComplaintMapScreen(staffQueue: true, showComplaints: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _index == 0 ? const SurveyVerificationScreen() : const SizedBox.shrink(),
          _map,
          _index == 2
              ? const NotificationScreen(showBackButton: false)
              : const SizedBox.shrink(),
          _index == 3 ? const ProfileScreen() : const SizedBox.shrink(),
        ],
      ),
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
