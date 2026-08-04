import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation/app_navigation.dart';
import '../services/auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'officer_reports_screen.dart';
import 'settings_screen.dart';

String _formatMobile(String? mobile) {
  if (mobile == null || mobile.length != 10) return mobile ?? '—';
  return '+91 ${mobile.substring(0, 5)} ${mobile.substring(5)}';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const _ProfileHeader(subtitle: 'Citizen'),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screen,
                ),
                child: Column(
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      )
                    else
                      _InfoCard(
                        rows: [
                          _InfoRowData(
                            icon: Icons.phone_rounded,
                            label: 'Mobile',
                            value: _formatMobile(_profile?.mobile),
                          ),
                        ],
                      ),
                    const SizedBox(height: AppSpacing.screen),
                    _NavCard(
                      items: [
                        if (widget.showReportsLink)
                          _NavItemData(
                            icon: Icons.bar_chart_rounded,
                            title: 'Reports',
                            onTap: () =>
                                push(context, const OfficerReportsScreen()),
                          ),
                        _NavItemData(
                          icon: Icons.translate_rounded,
                          title: 'भाषा बदलें',
                          onTap: () {},
                        ),
                        _NavItemData(
                          icon: Icons.settings_rounded,
                          title: 'Settings',
                          onTap: () => push(context, const SettingsScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await AuthService.logout();
                          if (!context.mounted) return;
                          pushReplacement(context, const LoginScreen());
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejectedText,
                          side: const BorderSide(color: AppColors.rejectedText),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Logout'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(AppSpacing.screen, topPadding + 24, 8, 48),
      decoration: const BoxDecoration(gradient: AppGradients.header),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Column(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 44,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFFFFF3E0),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: defaultHeaderActions(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.orangeTint,
                      foregroundColor: AppColors.primary,
                      child: Icon(rows[i].icon, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rows[i].label,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rows[i].value,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF212121),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.items});

  final List<_NavItemData> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.orangeTint,
                foregroundColor: AppColors.primary,
                child: Icon(items[i].icon, size: 19),
              ),
              title: Text(
                items[i].title,
                style: GoogleFonts.notoSansDevanagari(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF212121),
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9E9E9E),
              ),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}
