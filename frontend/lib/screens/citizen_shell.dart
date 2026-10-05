import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../widgets/location_gate.dart';
import 'citizen_profile_screen.dart';
import 'complaint_map_screen.dart';
import 'my_complaints_screen.dart';
import 'notification_screen.dart';
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
      const CitizenProfileScreen(),
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
      customBorder: const StadiumBorder(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F3E6) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1B6B43),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 2),
            Text(
              'Raise Issue',
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF1B6B43)),
            ),
          ],
        ),
      ),
    );
  }
}
