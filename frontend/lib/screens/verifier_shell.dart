import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'survey_verification_screen.dart';

/// Shared shell for the four upper stages of the asset-survey verification
/// escalation chain - BDPO, DDPO, XEN-PR, CEO-ZP. Each sees the same
/// Verify/Profile tabs; [SurveyVerificationScreen] adapts its queue and
/// actions to whichever of the four is actually signed in.
class VerifierShell extends StatefulWidget {
  const VerifierShell({super.key});

  @override
  State<VerifierShell> createState() => _VerifierShellState();
}

class _VerifierShellState extends State<VerifierShell> {
  int _index = 0;

  final _screens = const [
    SurveyVerificationScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
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
            icon: Icon(Icons.person_outline, size: 24),
            selectedIcon: Icon(Icons.person_rounded, size: 24),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
