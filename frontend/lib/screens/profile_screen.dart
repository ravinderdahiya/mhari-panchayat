import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../navigation/app_navigation.dart';
import '../services/auth_api.dart';
import '../services/auth_service.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'notification_screen.dart';
import 'officer_reports_screen.dart';
import 'settings_screen.dart';

const _green = Color(0xFF1B6B43);
const _orange = Color(0xFFF58220);

TextStyle _ts(double size, {Color? color, FontWeight weight = FontWeight.w500, double? spacing}) =>
    GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

String _formatMobile(String? mobile) {
  if (mobile == null || mobile.length != 10) return mobile ?? '—';
  return '+91 ${mobile.substring(0, 5)} ${mobile.substring(5)}';
}

// Mirrors the admin panel's `role.replace(/_/g, ' ')` convention (e.g.
// "gram_sachiv" -> "gram sachiv") so the same account reads the same way in
// both places. This screen is shared by every non-survey role (citizen,
// officer, cplo, bdpo, ddpo, gram sachiv, ...), so the label has to come from
// the signed-in user's actual role rather than being hardcoded.
String _roleLabel(String? role) {
  if (role == null || role.isEmpty) return '';
  return role.replaceAll('_', ' ').toUpperCase();
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.showReportsLink = false});

  final bool showReportsLink;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  UserProfile? _profile;
  // Null when the signed-in role has no complaint queue (stats row is hidden).
  ({int assigned, int pending, int completed})? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await AuthApi.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final queue = await ComplaintApi.getOfficerQueue();
      if (!mounted) return;
      final completed = queue
          .where((c) => c.status == ComplaintStatus.resolved || c.status == ComplaintStatus.closed)
          .length;
      final rejected = queue.where((c) => c.status == ComplaintStatus.rejected).length;
      setState(() {
        _stats = (assigned: queue.length, pending: queue.length - completed - rejected, completed: completed);
      });
    } catch (_) {
      // Roles without a complaint queue simply don't get the stats row.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final details = <_InfoRowData>[
      if ((p?.staffId ?? '').isNotEmpty) _InfoRowData(Icons.badge_rounded, 'Staff ID', p!.staffId!),
      if ((p?.email ?? '').isNotEmpty) _InfoRowData(Icons.email_rounded, 'Email', p!.email!),
      if ((p?.departmentName ?? '').isNotEmpty)
        _InfoRowData(Icons.account_balance_rounded, 'Department', p!.departmentName!),
      if ((p?.districtName ?? '').isNotEmpty) _InfoRowData(Icons.location_city_rounded, 'District', p!.districtName!),
      if ((p?.blockName ?? '').isNotEmpty) _InfoRowData(Icons.map_rounded, 'Block', p!.blockName!),
      if ((p?.panchayatName ?? '').isNotEmpty) _InfoRowData(Icons.holiday_village_rounded, 'Panchayat', p!.panchayatName!),
    ];

    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(
              name: p?.name,
              mobile: _formatMobile(p?.mobile),
              roleLabel: _roleLabel(p?.role),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 6, AppSpacing.screen, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (_stats != null) ...[
                      _StatsRow(stats: _stats!),
                      const SizedBox(height: 18),
                    ],
                    if (details.isNotEmpty) ...[
                      _SectionTitle('Official details'),
                      _InfoCard(rows: details),
                      const SizedBox(height: 18),
                    ],
                  ],
                  _SectionTitle('Account'),
                  _NavCard(
                    items: [
                      if (widget.showReportsLink)
                        _NavItemData(
                          icon: Icons.bar_chart_rounded,
                          color: _green,
                          title: 'Reports',
                          subtitle: 'Complaint summary and trends',
                          onTap: () => push(context, const OfficerReportsScreen()),
                        ),
                      _NavItemData(
                        icon: Icons.notifications_rounded,
                        color: _orange,
                        title: 'Notifications',
                        subtitle: 'Alerts and updates',
                        onTap: () => push(context, const NotificationScreen()),
                      ),
                      _NavItemData(
                        icon: Icons.translate_rounded,
                        color: const Color(0xFF3B6FD4),
                        title: 'Language',
                        subtitle: 'English / हिंदी',
                        onTap: () => push(context, const SettingsScreen()),
                      ),
                      _NavItemData(
                        icon: Icons.settings_rounded,
                        color: const Color(0xFF7C4DDB),
                        title: 'Settings',
                        subtitle: 'App preferences',
                        onTap: () => push(context, const SettingsScreen()),
                      ),
                      _NavItemData(
                        icon: Icons.headset_mic_rounded,
                        color: const Color(0xFF2FA05A),
                        title: 'Help & Support',
                        subtitle: 'FAQs, contact us',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Help & Support will be available soon')),
                        ),
                      ),
                      _NavItemData(
                        icon: Icons.info_rounded,
                        color: const Color(0xFF2556A8),
                        title: 'About Mhari Panchayat',
                        subtitle: 'App information and version',
                        onTap: () => showAboutDialog(
                          context: context,
                          applicationName: 'Mhari Panchayat',
                          applicationVersion: '1.0.0',
                          applicationLegalese: 'Development and Panchayats Department, Government of Haryana',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
                        backgroundColor: const Color(0xFFFDF1EE),
                        side: const BorderSide(color: Color(0xFFE3705A)),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text('Logout', style: _ts(15, weight: FontWeight.w600)),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
    child: Text(text, style: _ts(15, color: AppColors.ink, weight: FontWeight.w700)),
  );
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.mobile, required this.roleLabel});

  final String? name;
  final String mobile;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(AppSpacing.screen, topPadding + 10, AppSpacing.screen, 56),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3, 0.55, 1.0],
            colors: [Color(0xFFE9F1E6), Color(0xFFB9D3B4), Color(0xFF3F7D55), Color(0xFF1E5A3A)],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Color(0xFFFCE9D2), shape: BoxShape.circle),
                  child: SvgPicture.asset('assets/images/haryana_emblem.svg'),
                ),
                const SizedBox(width: 8),
                Text(
                  'Government\nof Haryana',
                  style: _ts(9.5, color: AppColors.ink, weight: FontWeight.w600).copyWith(height: 1.2),
                ),
                const Spacer(),
                Column(
                  children: [
                    Text('Mhari Panchayat', style: _ts(20, color: _green, weight: FontWeight.w700)),
                    Text(
                      'मेरी पंचायत - सशक्त पंचायत, समृद्ध हरियाणा',
                      style: _ts(8.5, color: _orange, weight: FontWeight.w600),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Color(0xFFE6EEF7), shape: BoxShape.circle),
                  child: Image.asset('assets/images/harsac_logo.png'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: const CircleAvatar(
                        radius: 44,
                        backgroundColor: Color(0xFFE3F0E8),
                        child: Icon(Icons.person_rounded, color: _green, size: 52),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2A22),
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
                        (name ?? '').isEmpty ? '—' : name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ts(24, color: Colors.white, weight: FontWeight.w700),
                      ),
                      Text(mobile, style: _ts(14, color: Colors.white.withValues(alpha: 0.95))),
                      const SizedBox(height: 6),
                      if (roleLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _green,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  roleLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _ts(11.5, color: Colors.white, weight: FontWeight.w600),
                                ),
                              ),
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

/// Soft wave along the bottom edge of the profile header.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 22);
    path.quadraticBezierTo(size.width * 0.25, size.height + 8, size.width * 0.55, size.height - 16);
    path.quadraticBezierTo(size.width * 0.82, size.height - 34, size.width, size.height - 12);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final ({int assigned, int pending, int completed}) stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: stats.assigned,
            label: 'Assigned',
            icon: Icons.assignment_rounded,
            background: const Color(0xFFE6F3EA),
            foreground: _green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: stats.pending,
            label: 'Pending',
            icon: Icons.schedule_rounded,
            background: const Color(0xFFFDEEDD),
            foreground: _orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: stats.completed,
            label: 'Completed',
            icon: Icons.check_rounded,
            background: const Color(0xFFE6F3EA),
            foreground: _green,
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 15),
          ),
          const SizedBox(height: 8),
          Text('$value', style: _ts(21, color: AppColors.ink, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: _ts(12, color: foreground, weight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Icon(rows[i].icon, size: 20, color: _green),
                  const SizedBox(width: 12),
                  Text(rows[i].label, style: _ts(13, color: AppColors.mutedText, weight: FontWeight.w400)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ts(
                        13.5,
                        color: rows[i].value.toLowerCase().startsWith('unassigned') ? _orange : AppColors.ink,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.items});

  final List<_NavItemData> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(11)),
                child: Icon(item.icon, color: Colors.white, size: 22),
              ),
              title: Text(item.title, style: _ts(14.5, color: AppColors.ink, weight: FontWeight.w600)),
              subtitle: Text(item.subtitle, style: _ts(12, color: AppColors.mutedText, weight: FontWeight.w400)),
              trailing: Icon(Icons.chevron_right_rounded, color: AppColors.ink),
              onTap: item.onTap,
            ),
          ),
      ],
    );
  }
}
