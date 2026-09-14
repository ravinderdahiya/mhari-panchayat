import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_role.dart';
import '../navigation/app_navigation.dart';
import '../services/auth_api.dart';
import '../services/auth_service.dart';
import '../services/survey_api.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

String _formatMobile(String? mobile) {
  if (mobile == null || mobile.length != 10) return mobile ?? '—';
  return '+91 ${mobile.substring(0, 5)} ${mobile.substring(5)}';
}

class SurveyorProfileScreen extends StatefulWidget {
  const SurveyorProfileScreen({super.key, this.embedded = false});

  /// Hides the close button when this screen is a bottom-nav tab.
  final bool embedded;

  @override
  State<SurveyorProfileScreen> createState() => _SurveyorProfileScreenState();
}

class _SurveyorProfileScreenState extends State<SurveyorProfileScreen> {
  String? _name;
  String? _staffId;
  String? _serverRole;
  UserProfile? _profile;
  int? _surveyCount;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await AuthService.getSession();
    if (mounted) {
      setState(() {
        _name = session?.officerName;
        _staffId = session?.staffId;
        _serverRole = session?.serverRole;
      });
    }

    try {
      final profile = await AuthApi.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _name = profile.name ?? _name;
          _staffId = profile.staffId ?? _staffId;
          _serverRole = profile.role;
          _loading = false;
        });
      }
      await AuthService.persistServerRole(profile.role);
    } catch (_) {
      final fieldRole = await AuthApi.resolvedFieldRole();
      if (mounted) {
        setState(() {
          if (fieldRole != null && fieldRole.isNotEmpty) {
            _serverRole = fieldRole;
          }
          _loading = false;
        });
      }
    }

    try {
      final surveys = await SurveyApi.getExistingAssets();
      if (mounted) setState(() => _surveyCount = surveys.length);
    } catch (_) {
      // Leave the count blank if it can't be loaded right now.
    }
  }

  List<_InfoRowData> get _rows {
    final profile = _profile;
    final rows = <_InfoRowData>[
      if ((profile?.name ?? _name ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.person_rounded,
          label: 'Name',
          value: profile?.name ?? _name!,
        ),
      _InfoRowData(
        icon: Icons.badge_rounded,
        label: 'Staff ID',
        value: profile?.staffId ?? _staffId ?? '—',
      ),
      if ((profile?.mobile ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.phone_rounded,
          label: 'Mobile',
          value: _formatMobile(profile!.mobile),
        ),
      if ((profile?.email ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.email_rounded,
          label: 'Email',
          value: profile!.email!,
        ),
      _InfoRowData(
        icon: Icons.verified_user_rounded,
        label: 'Role',
        value: FieldStaffCopy.roleLabel(profile?.role ?? _serverRole),
      ),
      if ((profile?.departmentName ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.account_balance_rounded,
          label: 'Department',
          value: profile!.departmentName!,
        ),
      if ((profile?.districtName ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.location_city_rounded,
          label: 'District',
          value: profile!.districtName!,
        ),
      if ((profile?.blockName ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.map_rounded,
          label: 'Block',
          value: profile!.blockName!,
        ),
      if ((profile?.panchayatName ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.home_work_rounded,
          label: 'Panchayat',
          value: profile!.panchayatName!,
        ),
      if ((profile?.memberId ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.credit_card_rounded,
          label: 'Member ID',
          value: profile!.memberId!,
        ),
      if ((profile?.familyId ?? '').isNotEmpty)
        _InfoRowData(
          icon: Icons.groups_rounded,
          label: 'Family ID',
          value: profile!.familyId!,
        ),
      _InfoRowData(
        icon: Icons.fact_check_rounded,
        label: 'Total Surveys Submitted',
        value: _surveyCount?.toString() ?? '—',
      ),
    ];
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(
              name: _name,
              serverRole: _serverRole,
              showClose: !widget.embedded,
            ),
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
                      _InfoCard(rows: _rows),
                    const SizedBox(height: AppSpacing.screen),
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.orangeTint,
                          foregroundColor: AppColors.primary,
                          child: Icon(Icons.settings_rounded, size: 19),
                        ),
                        title: Text(
                          'Settings',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF212121),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF9E9E9E),
                        ),
                        onTap: () => push(context, const SettingsScreen()),
                      ),
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
  const _ProfileHeader({
    required this.name,
    this.serverRole,
    this.showClose = true,
  });

  final String? name;
  final String? serverRole;
  final bool showClose;

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
                name ?? FieldStaffCopy.profileFallbackName(serverRole),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                FieldStaffCopy.profileSubtitle(serverRole),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFFFFF3E0),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (showClose)
            Positioned(
              top: 0,
              right: 0,
              child: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
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
