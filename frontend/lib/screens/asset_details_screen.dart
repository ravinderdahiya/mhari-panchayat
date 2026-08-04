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
  const AssetDetailsScreen({super.key, required this.assetId});

  final String assetId;

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

  @override
  Widget build(BuildContext context) {
    final asset = _asset;

    return AppScaffold(
      title: asset?.assetName ?? 'Asset Details',
      subtitle: asset?.assetTypeName,
      body: _loading
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
          : _buildBody(context, asset),
    );
  }

  Widget _buildBody(BuildContext context, AssetDetail asset) {
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
