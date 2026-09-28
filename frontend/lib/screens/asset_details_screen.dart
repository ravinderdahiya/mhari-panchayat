import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/api_config.dart';
import '../models/asset.dart';
import '../models/survey.dart';
import '../services/asset_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../widgets/common_widgets.dart';
import '../widgets/photo_viewer.dart';

class AssetDetailsScreen extends StatefulWidget {
  const AssetDetailsScreen({
    super.key,
    required this.assetId,
    this.onUpdateSurvey,
    this.survey,
  });

  final String assetId;

  /// Surveyor-only action: when provided, a bottom button lets the surveyor
  /// jump into the survey form for this asset. Citizen callers (e.g. the
  /// complaint map) simply omit this and get a read-only view.
  final VoidCallback? onUpdateSurvey;

  /// The full Survey record, when this screen was opened from the
  /// surveyor's own "Existing Asset" list (see AssetSurveyScreen) - carries
  /// the review-chain data (reviewStatus, reviews, requiresTechnicalReview)
  /// the generic /api/assets/:id lookup below doesn't have. Drives whether
  /// Update Survey shows at all, and the status timeline in its place.
  final Survey? survey;

  @override
  State<AssetDetailsScreen> createState() => _AssetDetailsScreenState();
}

class _AssetDetailsScreenState extends State<AssetDetailsScreen> {
  bool _loading = true;
  AssetDetail? _asset;
  String? _error;

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
      final asset = await AssetApi.getAssetById(widget.assetId);
      if (!mounted) return;
      setState(() {
        _asset = asset;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'एसेट विवरण लोड नहीं हो पाया।';
        _loading = false;
      });
    }
  }

  Color _conditionColor(SurveyCondition condition) {
    return switch (condition) {
      SurveyCondition.good => AppColors.resolvedText,
      SurveyCondition.fair => AppColors.inProgressText,
      SurveyCondition.poor => AppColors.pendingText,
      SurveyCondition.damaged => AppColors.rejectedText,
    };
  }

  // Editable while it's still only the surveyor's own draft ('submitted' -
  // not yet forwarded) or Gram Sachiv has sent it back for correction
  // ('returned'). Once it's anywhere else in the review chain, editing
  // would silently change what's under review - show the status timeline
  // instead. No survey record (e.g. a citizen opening this from the
  // complaint map) falls back to the old always-editable behaviour.
  bool get _canUpdateSurvey {
    final status = widget.survey?.reviewStatus;
    return status == null || status == 'submitted' || status == 'returned';
  }

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    final survey = widget.survey;

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Text(
              _error!,
              style: GoogleFonts.poppins(color: AppColors.mutedText),
            ),
          )
        : asset == null
        ? const SizedBox.shrink()
        : _buildBody(context, asset, survey);

    final showUpdateButton =
        widget.onUpdateSurvey != null && asset != null && _canUpdateSurvey;

    return AppScaffold(
      title: asset?.assetName ?? 'Asset Details',
      subtitle: asset?.assetTypeName,
      body: !showUpdateButton
          ? content
          : Column(
              children: [
                Expanded(child: content),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.gapSm,
                    AppSpacing.screen,
                    AppSpacing.screen,
                  ),
                  child: GradientButton(
                    onPressed: widget.onUpdateSurvey,
                    label: 'Update Survey',
                    icon: Icons.edit_note_rounded,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody(BuildContext context, AssetDetail asset, Survey? survey) {
    return ListView(
      // Extra top padding - AppScaffold's body sits in a rounded card
      // pulled up 20px to overlap the gradient header (see
      // common_widgets.dart's AppScaffold), which otherwise clips the
      // asset name/ID row right at the top of this list.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.screen + 20,
        AppSpacing.screen,
        AppSpacing.screen,
      ),
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
                assetTypeIcon(asset.iconKey ?? 'apartment'),
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
                    asset.assetName,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    asset.assetId,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _conditionColor(asset.condition).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                asset.condition.label,
                style: TextStyle(
                  color: _conditionColor(asset.condition),
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
            ('District', asset.district),
            ('Block', asset.block),
            ('Panchayat', asset.panchayat),
            ('Village', asset.village),
            if (asset.latitude != null && asset.longitude != null)
              (
                'GPS',
                '${asset.latitude!.toStringAsFixed(6)}, ${asset.longitude!.toStringAsFixed(6)}',
              ),
            ('Survey Date', _formatDate(asset.surveyDate)),
          ],
        ),
        const SizedBox(height: AppSpacing.gap),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total',
                value: asset.totalComplaints.toString(),
                icon: Icons.report_rounded,
                color: AppColors.primary,
                backgroundColor: AppColors.orangeTint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'Resolved',
                value: asset.resolvedCount.toString(),
                icon: Icons.check_circle_rounded,
                color: AppColors.resolvedText,
                backgroundColor: AppColors.greenTint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: 'Pending',
                value: asset.pendingCount.toString(),
                icon: Icons.hourglass_empty_rounded,
                color: AppColors.pendingText,
                backgroundColor: AppColors.orangeTint,
              ),
            ),
          ],
        ),
        if (asset.description != null && asset.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.screen),
          Text(
            'Description',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            asset.description!,
            style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
          ),
        ],
        if (asset.photoUrls.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.screen),
          Text(
            'Survey Photos',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final path in asset.photoUrls)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => showPhotoViewer(
                      context,
                      imageUrl: '${ApiConfig.baseUrl}$path',
                    ),
                    child: Image.network(
                      '${ApiConfig.baseUrl}$path',
                      width: 92,
                      height: 92,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 92,
                        height: 92,
                        color: AppColors.greyBg,
                        child: Icon(
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
        if (survey != null && !_canUpdateSurvey) ...[
          const SizedBox(height: AppSpacing.screen),
          Text(
            'Status',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _StatusTimeline(survey: survey),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = date.day.toString().padLeft(2, '0');
    return '$day ${months[date.month - 1]} ${date.year}';
  }
}

enum _StepState { completed, current, rejected, pending }

class _TimelineStep {
  const _TimelineStep({
    required this.label,
    required this.state,
    this.actionLabel,
    this.date,
  });

  final String label;
  final _StepState state;
  final String? actionLabel;
  final DateTime? date;
}

const Map<String, String> _timelineActionLabel = {
  'reviewed': 'Reviewed',
  'forwarded': 'Forwarded',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'returned': 'Returned for correction',
};

/// CPLO (Submitted) -> Gram Sachiv -> BDPO -> DDPO, each marked completed /
/// current / rejected / pending from the survey's own review-chain audit
/// trail (survey.reviews) rather than just reviewStatus, so a rejection
/// shows exactly which stage it happened at instead of just "not reached".
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.survey});

  final Survey survey;

  SurveyReview? _lastByRole(String role, List<String> actions) {
    final matches = survey.reviews
        .where((r) => r.actorRole == role && actions.contains(r.action))
        .toList();
    return matches.isEmpty ? null : matches.last;
  }

  _TimelineStep _stepFor({
    required String label,
    required String role,
    required List<String> completingActions,
    required List<String> currentStatuses,
  }) {
    final rejection = _lastByRole(role, const ['rejected']);
    if (rejection != null) {
      return _TimelineStep(
        label: label,
        state: _StepState.rejected,
        actionLabel: _timelineActionLabel['rejected'],
        date: rejection.createdAt,
      );
    }

    final completion = _lastByRole(role, completingActions);
    if (completion != null) {
      return _TimelineStep(
        label: label,
        state: _StepState.completed,
        actionLabel: _timelineActionLabel[completion.action] ?? completion.action,
        date: completion.createdAt,
      );
    }

    if (currentStatuses.contains(survey.reviewStatus)) {
      return _TimelineStep(label: label, state: _StepState.current);
    }

    return _TimelineStep(label: label, state: _StepState.pending);
  }

  @override
  Widget build(BuildContext context) {
    final cploForward = _lastByRole('cplo', const ['forwarded']) ??
        _lastByRole('surveyor', const ['forwarded']);
    final cploStep = _TimelineStep(
      label: 'CPLO (Submitted)',
      state: _StepState.completed,
      actionLabel: 'Submitted',
      date: cploForward?.createdAt ?? survey.createdAt,
    );

    final gramSachivStep = _stepFor(
      label: 'Gram Sachiv',
      role: 'gram_sachiv',
      completingActions: const ['forwarded'],
      currentStatuses: const ['pending', 'gram_sachiv_reviewed'],
    );
    final bdpoStep = _stepFor(
      label: 'BDPO',
      role: 'bdpo',
      completingActions: const ['forwarded'],
      currentStatuses: const ['gram_sachiv_approved', 'bdpo_reviewed'],
    );
    final ddpoStep = _stepFor(
      label: 'DDPO',
      role: 'ddpo',
      completingActions: const ['approved'],
      currentStatuses: const ['bdpo_forwarded', 'ddpo_reviewed'],
    );

    final steps = [cploStep, gramSachivStep, bdpoStep, ddpoStep];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _StatusTimelineRow(step: steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }
}

class _StatusTimelineRow extends StatelessWidget {
  const _StatusTimelineRow({required this.step, required this.isLast});

  final _TimelineStep step;
  final bool isLast;

  Color get _dotColor => switch (step.state) {
    _StepState.completed => AppColors.resolvedText,
    _StepState.current => AppColors.primary,
    _StepState.rejected => AppColors.rejectedText,
    _StepState.pending => AppColors.mutedText,
  };

  IconData get _icon => switch (step.state) {
    _StepState.completed => Icons.check_circle_rounded,
    _StepState.current => Icons.radio_button_checked_rounded,
    _StepState.rejected => Icons.cancel_rounded,
    _StepState.pending => Icons.radio_button_unchecked_rounded,
  };

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = date.day.toString().padLeft(2, '0');
    return '$day ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = step.actionLabel != null
        ? '${step.actionLabel}${step.date != null ? ' · ${_formatDate(step.date!)}' : ''}'
        : switch (step.state) {
            _StepState.current => 'In progress',
            _StepState.pending => 'Not reached yet',
            _ => '',
          };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(_icon, color: _dotColor, size: 20),
            if (!isLast)
              Container(width: 2, height: 28, color: AppColors.border),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: step.state == _StepState.pending
                        ? AppColors.mutedText
                        : null,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: _dotColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
