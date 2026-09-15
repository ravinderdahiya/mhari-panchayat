import 'package:flutter/material.dart';

import '../widgets/location_gate.dart';
import 'asset_survey_screen.dart';
import 'complaint_map_screen.dart';
import 'surveyor_profile_screen.dart';

/// CPLO handles field asset surveys only, never complaints - Home is the
/// survey form, Map is the asset-survey map with complaints switched off
/// entirely (no complaint markers, legend, or status filter), and there is
/// deliberately no Tasks/complaint-queue tab.
class CploShell extends StatefulWidget {
  const CploShell({super.key});

  @override
  State<CploShell> createState() => _CploShellState();
}

class _CploShellState extends State<CploShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = const [
      AssetSurveyScreen(embedded: true),
      LocationGate(
        child: ComplaintMapScreen(staffQueue: true, showComplaints: false),
      ),
      SurveyorProfileScreen(embedded: true),
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
            icon: Icon(Icons.person_outline, size: 24),
            selectedIcon: Icon(Icons.person_rounded, size: 24),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
