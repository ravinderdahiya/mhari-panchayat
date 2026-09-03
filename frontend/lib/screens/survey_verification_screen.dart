import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/survey.dart';
import '../services/survey_review_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../widgets/common_widgets.dart';
import 'survey_review_detail_screen.dart';

/// Gram Sachiv's queue of CPLO-submitted surveys for their own panchayat -
/// the backend already scopes `/api/surveys` to `panchayat_id` for this
/// role, so this screen only has to pick the review_status tab.
class SurveyVerificationScreen extends StatefulWidget {
  const SurveyVerificationScreen({super.key});

  @override
  State<SurveyVerificationScreen> createState() =>
      _SurveyVerificationScreenState();
}

class _SurveyVerificationScreenState extends State<SurveyVerificationScreen> {
  String _status = 'pending';
  bool _loading = true;
  String? _error;
  List<Survey> _surveys = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    'gram_sachiv_approved' => AppColors.resolvedText,
    'rejected' => AppColors.rejectedText,
    _ => AppColors.pendingText,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientHeader(
            title: 'Survey Verification',
            subtitle: 'CPLO सर्वे सत्यापित करें · अपनी पंचायत',
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
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final s in const [
                              ('pending', 'Pending'),
                              ('returned', 'Returned'),
                              ('gram_sachiv_approved', 'Verified'),
                              ('rejected', 'Rejected'),
                            ])
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  24,
                                ),
                                itemCount: _surveys.length,
                                itemBuilder: (context, index) {
                                  final survey = _surveys[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _SurveyCard(
                                      survey: survey,
                                      onTap: () async {
                                        final changed = await Navigator.of(
                                          context,
                                        ).push<bool>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                SurveyReviewDetailScreen(
                                                  survey: survey,
                                                ),
                                          ),
                                        );
                                        if (changed == true) _load();
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
