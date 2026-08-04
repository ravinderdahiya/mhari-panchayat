import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../widgets/location_gate.dart';
import 'complaint_map_screen.dart';
import 'my_complaints_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'report_issue_screen.dart';

class CitizenShell extends StatefulWidget {
  const CitizenShell({super.key});

  @override
  State<CitizenShell> createState() => _CitizenShellState();
}

class _CitizenShellState extends State<CitizenShell> {
  int _index = 0;
  int _refreshTick = 0;

  Future<void> _openNewComplaint() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportIssueScreen()));
    setState(() => _refreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LocationGate(
        key: ValueKey('home_$_refreshTick'),
        child: const ComplaintMapScreen(),
      ),
      MyComplaintsScreen(key: ValueKey('complaints_$_refreshTick')),
      const NotificationScreen(showBackButton: false),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: Container(
        color: AppColors.background,
        child: SafeArea(
          top: false,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: SizedBox(
              height: 76,
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: _NavIcon(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        selected: _index == 0,
                        onTap: () => setState(() => _index = 0),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _NavIcon(
                        icon: Icons.assignment_outlined,
                        selectedIcon: Icons.assignment_rounded,
                        label: 'Complaints',
                        selected: _index == 1,
                        onTap: () => setState(() => _index = 1),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _NewComplaintButton(onTap: _openNewComplaint),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _NavIcon(
                        icon: Icons.notifications_outlined,
                        selectedIcon: Icons.notifications_rounded,
                        label: 'Alerts',
                        selected: _index == 2,
                        onTap: () => setState(() => _index = 2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _NavIcon(
                        icon: Icons.person_outline,
                        selectedIcon: Icons.person_rounded,
                        label: 'Profile',
                        selected: _index == 3,
                        onTap: () => setState(() => _index = 3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.navInactive;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewComplaintButton extends StatelessWidget {
  const _NewComplaintButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.header,
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
