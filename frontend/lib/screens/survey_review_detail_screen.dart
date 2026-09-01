import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/survey.dart';
import '../services/survey_review_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../widgets/common_widgets.dart';
import '../widgets/photo_viewer.dart';

class SurveyReviewDetailScreen extends StatefulWidget {
  const SurveyReviewDetailScreen({super.key, required this.survey});

  final Survey survey;

  @override
  State<SurveyReviewDetailScreen> createState() =>
      _SurveyReviewDetailScreenState();
}

class _SurveyReviewDetailScreenState extends State<SurveyReviewDetailScreen> {
  late Survey _survey = widget.survey;
  bool _submitting = false;
  String? _error;

  Color _conditionColor(SurveyCondition condition) {
    return switch (condition) {
      SurveyCondition.good => AppColors.resolvedText,
      SurveyCondition.fair => AppColors.inProgressText,
      SurveyCondition.poor => AppColors.pendingText,
      SurveyCondition.damaged => AppColors.rejectedText,
    };
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = date.day.toString().padLeft(2, '0');
    return '$day ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _approve() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await SurveyReviewApi.approve(_survey.id);
      if (!mounted) return;
      setState(() => _survey = updated);
      Navigator.of(context).pop(true);
    } on SurveyReviewApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await SurveyReviewApi.reject(_survey.id, reason.trim());
      if (!mounted) return;
      setState(() => _survey = updated);
      Navigator.of(context).pop(true);
    } on SurveyReviewApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final survey = _survey;
    final isPending = (survey.reviewStatus ?? 'pending') == 'pending';

    return AppScaffold(
      title: survey.assetName.trim().isNotEmpty
          ? survey.assetName
          : (survey.assetTypeName ?? 'Survey'),
      subtitle: survey.assetTypeName,
      body: Column(
        children: [
          Expanded(child: _buildBody(context, survey)),
          if (isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.gapSm,
                AppSpacing.screen,
                AppSpacing.screen,
              ),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: GoogleFonts.poppins(
                        color: AppColors.rejectedText,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _reject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.rejectedText,
                            side: const BorderSide(
                              color: AppColors.rejectedText,
                            ),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          onPressed: _submitting ? null : _approve,
                          label: _submitting ? 'कृपया प्रतीक्षा करें...' : 'Approve',
                          icon: Icons.check_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, Survey survey) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screen),
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.orangeTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                assetTypeIcon(survey.assetTypeIconKey ?? 'apartment'),
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    survey.assetId,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                  ),
                  Text(
                    'Surveyed by ${survey.surveyedByName ?? '—'}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _conditionColor(survey.condition).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                survey.condition.label,
                style: TextStyle(
                  color: _conditionColor(survey.condition),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.screen),
        DetailPanel(
          rows: [
            ('District', survey.district),
            ('Panchayat', survey.panchayat),
            ('Village', survey.village),
            if (survey.latitude != null && survey.longitude != null)
              (
                'GPS',
                '${survey.latitude!.toStringAsFixed(6)}, ${survey.longitude!.toStringAsFixed(6)}',
              ),
            ('Survey Date', _formatDate(survey.surveyDate)),
          ],
        ),
        if (survey.rejectionReason != null &&
            survey.rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.gap),
          InfoStrip(
            icon: Icons.info_outline_rounded,
            text: 'Rejected: ${survey.rejectionReason}',
          ),
        ],
        if (survey.description != null && survey.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.screen),
          Text(
            'Description',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            survey.description!,
            style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
          ),
        ],
        if (survey.photoUrls.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.screen),
          Text(
            'Survey Photos',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in survey.photoUrls)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => showPhotoViewer(context, imageUrl: url),
                    child: Image.network(
                      url,
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 92,
                        height: 92,
                        color: AppColors.greyBg,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject survey'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'Reason for rejection…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.rejectedText,
          ),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
