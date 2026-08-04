import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../navigation/app_navigation.dart';
import '../services/auth_service.dart';
import '../services/survey_api.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class SurveyorProfileScreen extends StatefulWidget {
  const SurveyorProfileScreen({super.key});

  @override
  State<SurveyorProfileScreen> createState() => _SurveyorProfileScreenState();
}

class _SurveyorProfileScreenState extends State<SurveyorProfileScreen> {
  String? _name;
  String? _staffId;
  int? _surveyCount;

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
      });
    }

    try {
      final surveys = await SurveyApi.getExistingAssets();
      if (mounted) setState(() => _surveyCount = surveys.length);
    } catch (_) {
      // Leave the count blank if it can't be loaded right now.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _ProfileHeader(name: _name),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screen,
                ),
                child: Column(
                  children: [
                    _InfoCard(
                      rows: [
                        _InfoRowData(
                          icon: Icons.badge_rounded,
                          label: 'Staff ID',
                          value: _staffId ?? '—',
                        ),
                        const _InfoRowData(
                          icon: Icons.verified_user_rounded,
                          label: 'Role',
                          value: 'Surveyor',
                        ),
                        _InfoRowData(
                          icon: Icons.fact_check_rounded,
                          label: 'Total Surveys Submitted',
                          value: _surveyCount?.toString() ?? '—',
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
  const _ProfileHeader({required this.name});

  final String? name;

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
                name ?? 'Surveyor',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Field Asset Survey',
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
