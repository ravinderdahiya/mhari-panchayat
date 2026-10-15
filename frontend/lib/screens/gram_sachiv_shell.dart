import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'survey_verification_screen.dart';
import '../widgets/adaptive_nav_scaffold.dart';

class GramSachivShell extends StatefulWidget {
  const GramSachivShell({super.key});

  @override
  State<GramSachivShell> createState() => _GramSachivShellState();
}

class _GramSachivShellState extends State<GramSachivShell> {
  int _index = 0;

  final _screens = const [
    SurveyVerificationScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveNavScaffold(
      body: _screens[_index],
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
    );
  }
}
