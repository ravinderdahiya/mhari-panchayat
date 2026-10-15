import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/survey.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/survey_review_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../utils/responsive.dart';
import '../widgets/common_widgets.dart';
import 'survey_review_detail_screen.dart';

/// Verification queue for any of the five escalation-chain stages - Gram
/// Sachiv, BDPO, DDPO, XEN-PR, CEO-ZP. The backend already scopes
/// `/api/surveys` to the signed-in reviewer's own jurisdiction (panchayat/
/// block/district), so this screen only has to pick the review_status tab
/// appropriate for whichever of the five is signed in.
class SurveyVerificationScreen extends StatefulWidget {
  const SurveyVerificationScreen({super.key});

  @override
  State<SurveyVerificationScreen> createState() =>
      _SurveyVerificationScreenState();
}

class _SurveyVerificationScreenState extends State<SurveyVerificationScreen> {
  String? _serverRole;
  String _status = 'pending';
  bool _loading = true;
  String? _error;
  List<Survey> _surveys = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final session = await AuthService.getSession();
    if (!mounted) return;
    setState(() {
      _serverRole = session?.serverRole;
      _status = VerifierCopy.inboxStatus(_serverRole);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final surveys = await SurveyReviewApi.getQueue(reviewStatus: _status);
      if (!mounted) return;
      setState(() {
        _surveys = surveys;
        _loading = false;
      });
    } on SurveyReviewApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _switchStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _load();
  }

  Color _statusColor(String status) => switch (status) {
    'gram_sachiv_approved' || 'bdpo_forwarded' || 'ddpo_approved' ||
    'xen_forwarded' || 'approved' => AppColors.resolvedText,
    'rejected' => AppColors.rejectedText,
    _ => AppColors.pendingText,
  };

  @override
  Widget build(BuildContext context) {
    final roleLabel = VerifierCopy.roleLabel(_serverRole);
    final roleSubtitle = VerifierCopy.roleSubtitle(_serverRole);
    final isGramSachiv = (_serverRole ?? '').trim().toLowerCase() == 'gram_sachiv';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientHeader(
            title: isGramSachiv ? 'Survey Verification' : '$roleLabel Verification',
            subtitle: isGramSachiv
                ? 'Survey Verification by Gram Sachiv'
                : roleSubtitle,
            tabletMaxWidth: Breakpoints.wide,
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Material(
                color: AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: context.isTablet
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildContent(constraints.maxWidth),
                      )
                    : _buildContent(null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _surveyCard(Survey survey) {
    return _SurveyCard(
      survey: survey,
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => SurveyReviewDetailScreen(survey: survey),
          ),
        );
        if (changed == true) _load();
      },
    );
  }

  /// [tabletWidth] is null on phones (original single-column list). On
  /// tablets content is centred at [Breakpoints.wide] and the survey cards
  /// flow into 2-3 columns.
  Widget _buildContent(double? tabletWidth) {
    final gutter = tabletWidth == null
        ? 16.0
        : centeredGutter(tabletWidth, Breakpoints.wide, min: 16);
    final columns = tabletWidth == null
        ? 1
        : tabletColumns(context, tabletWidth);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in VerifierCopy.statusTabs(_serverRole))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _StatusChip(
                      label: s.$2,
                      selected: _status == s.$1,
                      color: _statusColor(s.$1),
                      onTap: () => _switchStatus(s.$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _MessageList(
                    message: _error!,
                    icon: Icons.error_outline_rounded,
                  )
                : _surveys.isEmpty
                ? const _MessageList(
                    message: 'इस स्थिति में कोई सर्वे नहीं है',
                    icon: Icons.inbox_outlined,
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 24),
                    // Tablets: one item per row of [columns] cards.
                    itemCount: (_surveys.length / columns).ceil(),
                    itemBuilder: (context, index) {
                      if (columns == 1) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _surveyCard(_surveys[index]),
                        );
                      }
                      final start = index * columns;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = start; i < start + columns; i++) ...[
                              if (i > start) const SizedBox(width: 8),
                              Expanded(
                                child: i < _surveys.length
                                    ? _surveyCard(_surveys[i])
                                    : const SizedBox(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : AppColors.greyBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? color : AppColors.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 40, color: AppColors.mutedText),
        const SizedBox(height: 12),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: AppColors.mutedText),
          ),
        ),
      ],
    );
  }
}

class _SurveyCard extends StatelessWidget {
  const _SurveyCard({required this.survey, required this.onTap});

  final Survey survey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeName = survey.assetTypeName ?? survey.assetTypeId;
    final name = survey.assetName.trim().isNotEmpty
        ? survey.assetName
        : typeName;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.orangeTint,
          foregroundColor: AppColors.primary,
          child: Icon(
            assetTypeIcon(survey.assetTypeIconKey ?? 'apartment'),
            size: 20,
          ),
        ),
        title: Text(
          name,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'By: ${survey.surveyedByName ?? '—'}\nVillage: ${survey.village}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.mutedText,
            height: 1.35,
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
