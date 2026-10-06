import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../navigation/app_navigation.dart';
import '../services/auth_api.dart';
import '../services/auth_service.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../widgets/flipping_logo.dart';
import 'login_screen.dart';
import 'my_complaints_screen.dart';
import 'notification_screen.dart';
import 'settings_screen.dart';

// Poppins for all text (titles w500, subtitles w400); Noto Sans
// Devanagari isn't in the Plex family, so it rides along as a fallback for
// any Hindi text (e.g. "हिंदी" in the Language row) rather than the primary.
final String _hindiFallback = GoogleFonts.notoSansDevanagari().fontFamily!;

const _mockGreen = Color(0xFF1B6B43);
const _mockOrange = Color(0xFFF58220);

TextStyle _titleStyle(double size, {Color? color, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
    ).copyWith(fontFamilyFallback: [_hindiFallback]);

TextStyle _subtitleStyle(double size, {Color? color}) => GoogleFonts.poppins(
  fontSize: size,
  fontWeight: FontWeight.w400,
  color: color,
).copyWith(fontFamilyFallback: [_hindiFallback]);

/// Citizen-facing Profile tab: identity header, complaint stat counters and
/// an account menu. Distinct from [ProfileScreen] (shared by every staff
/// role) because the stat counters and "Registered Citizen" badge here only
/// make sense for a citizen account.
class CitizenProfileScreen extends StatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  State<CitizenProfileScreen> createState() => _CitizenProfileScreenState();
}

class _CitizenProfileScreenState extends State<CitizenProfileScreen> {
  bool _loading = true;
  UserProfile? _profile;
  int _total = 0;
  int _inProgress = 0;
  int _resolved = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final profile = await AuthApi.getProfile();
      final complaints = await ComplaintApi.getMine();
      if (!mounted) return;
      final resolved = complaints
          .where((c) => c.status == ComplaintStatus.resolved || c.status == ComplaintStatus.closed)
          .length;
      final rejected = complaints.where((c) => c.status == ComplaintStatus.rejected).length;
      setState(() {
        _profile = profile;
        _total = complaints.length;
        _resolved = resolved;
        _inProgress = complaints.length - resolved - rejected;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _CitizenProfileHeader(profile: _profile),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      4,
                      AppSpacing.screen,
                      24,
                    ),
                    child: Column(
                      children: [
                        _StatsRow(total: _total, inProgress: _inProgress, resolved: _resolved),
                        const SizedBox(height: 10),
                        _CitizenNavCard(
                          items: [
                            _NavEntry(
                              icon: Icons.assignment_rounded,
                              color: _mockGreen,
                              title: 'My Complaints',
                              filled: true,
                              subtitle: 'View and track your complaints',
                              onTap: () => push(context, const MyComplaintsScreen()),
                            ),
                            _NavEntry(
                              icon: Icons.notifications_rounded,
                              color: _mockOrange,
                              title: 'Notifications',
                              filled: true,
                              subtitle: 'Manage alerts and updates',
                              onTap: () => push(context, const NotificationScreen()),
                            ),
                            _NavEntry(
                              icon: Icons.translate_rounded,
                              color: const Color(0xFF3B82F6),
                              title: 'Language',
                              subtitle: 'English / हिंदी',
                              onTap: () => push(context, const SettingsScreen()),
                            ),
                            _NavEntry(
                              icon: Icons.settings_rounded,
                              color: const Color(0xFF8B5CF6),
                              title: 'Settings',
                              subtitle: 'App preferences',
                              onTap: () => push(context, const SettingsScreen()),
                            ),
                            _NavEntry(
                              icon: Icons.support_agent_rounded,
                              color: const Color(0xFF14B8A6),
                              title: 'Help & Support',
                              subtitle: 'FAQs, contact us',
                              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Help & Support will be available soon')),
                              ),
                            ),
                            _NavEntry(
                              icon: Icons.info_rounded,
                              color: const Color(0xFF2563EB),
                              title: 'About Mhari Panchayat',
                              subtitle: 'App information and version',
                              onTap: () => showAboutDialog(
                                context: context,
                                applicationName: 'Mhari Panchayat',
                                applicationVersion: '1.0.0',
                                applicationLegalese:
                                    'Development and Panchayats Department, Government of Haryana',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await AuthService.logout();
                              if (!context.mounted) return;
                              pushReplacement(context, const LoginScreen());
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFD9482B),
                              side: const BorderSide(color: Color(0xFFE3705A)),
                              minimumSize: const Size.fromHeight(44),
                              backgroundColor: const Color(0xFFFDF1EE),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: Text('Logout', style: _titleStyle(14, weight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CitizenProfileHeader extends StatelessWidget {
  const _CitizenProfileHeader({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final mobile = profile?.mobile;
    final formattedMobile = (mobile != null && mobile.length == 10)
        ? '+91 ${mobile.substring(0, 5)} ${mobile.substring(5)}'
        : (mobile ?? '—');

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(AppSpacing.screen, topPadding + 10, AppSpacing.screen, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.34, 0.62, 1.0],
            colors: [Color(0xFFE4EFE0), Color(0xFFB9D3B4), Color(0xFF3F7D55), Color(0xFF1E5A3A)],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const FlippingLogo(size: 38),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Mahari ', style: _titleStyle(20, color: _mockGreen, weight: FontWeight.w700)),
                          TextSpan(text: 'Panchayat', style: _titleStyle(20, color: _mockOrange, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Text(
                      'मेरी पंचायत - सशक्त पंचायत, समृद्ध हरियाणा',
                      style: _subtitleStyle(8.5, color: AppColors.ink),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: const CircleAvatar(
                        radius: 40,
                        backgroundColor: Color(0xFFE9F0E6),
                        child: Icon(Icons.person_rounded, color: _mockGreen, size: 46),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _mockGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Citizen ${profile?.id ?? ''}',
                        style: _titleStyle(20, color: Colors.white, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(formattedMobile, style: _subtitleStyle(14, color: Colors.white.withValues(alpha: 0.92))),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F3E6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: _mockGreen, size: 14),
                            const SizedBox(width: 5),
                            Text('Registered Citizen', style: _titleStyle(11.5, color: _mockGreen)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft concave wave along the bottom edge of the profile header.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 26);
    path.quadraticBezierTo(size.width * 0.25, size.height + 6, size.width * 0.55, size.height - 18);
    path.quadraticBezierTo(size.width * 0.82, size.height - 36, size.width, size.height - 14);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.total, required this.inProgress, required this.resolved});

  final int total;
  final int inProgress;
  final int resolved;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: total,
            label: 'Total Complaints',
            icon: Icons.assignment_rounded,
            background: const Color(0xFFE6F3EA),
            foreground: _mockGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: inProgress,
            label: 'In Progress',
            icon: Icons.schedule_rounded,
            background: const Color(0xFFFDEEDD),
            foreground: _mockOrange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: resolved,
            label: 'Resolved',
            icon: Icons.check_rounded,
            background: const Color(0xFFE6F3EA),
            foreground: _mockGreen,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 13),
          ),
          const SizedBox(height: 4),
          Text('$value', style: _titleStyle(18, color: AppColors.ink, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: _subtitleStyle(10.5, color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _NavEntry {
  const _NavEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  final bool filled;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _CitizenNavCard extends StatelessWidget {
  const _CitizenNavCard({required this.items});

  final List<_NavEntry> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.filled ? item.color : item.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.filled ? Colors.white : item.color, size: 19),
              ),
              title: Text(item.title, style: _titleStyle(13.5, color: AppColors.ink, weight: FontWeight.w600)),
              subtitle: Text(item.subtitle, style: _subtitleStyle(11, color: AppColors.mutedText)),
              trailing: Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
              onTap: item.onTap,
            ),
          ),
      ],
    );
  }
}
