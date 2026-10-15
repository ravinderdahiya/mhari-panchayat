import 'package:flutter/material.dart';

import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/common_widgets.dart';

class OfficerReportsScreen extends StatefulWidget {
  const OfficerReportsScreen({super.key});

  @override
  State<OfficerReportsScreen> createState() => _OfficerReportsScreenState();
}

class _OfficerReportsScreenState extends State<OfficerReportsScreen> {
  OfficerReportSummary? _reports;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await ComplaintApi.getOfficerReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Reports could not be loaded from server.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return AppScaffold(
      title: 'Reports',
      showBackButton: false,
      tabletMaxWidth: Breakpoints.wide,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: context.isTablet
                  ? LayoutBuilder(
                      builder: (context, constraints) =>
                          _buildTabletBody(reports, constraints.maxWidth),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.screen),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: StatCard(
                                label: 'Resolved',
                                value: (reports?.resolved ?? 0).toString(),
                                icon: Icons.task_alt_rounded,
                                color: AppColors.resolvedText,
                                backgroundColor: AppColors.greenTint,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.gap),
                            Expanded(
                              child: StatCard(
                                label: 'Avg. Days',
                                value:
                                    reports?.averageResolutionDays?.toStringAsFixed(
                                      1,
                                    ) ??
                                    '—',
                                icon: Icons.timer_rounded,
                                color: AppColors.inProgressText,
                                backgroundColor: AppColors.blueTint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.screen),
                        const SectionTitle(title: 'Category-wise Resolution'),
                        if (reports == null || reports.categories.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text('No report data available.')),
                          )
                        else
                          for (final category in reports.categories)
                            ReportRow(
                              label: category.name,
                              value: '${(category.percent * 100).round()}%',
                              percent: category.percent,
                            ),
                        const SizedBox(height: AppSpacing.screen),
                        const ExportPanel(),
                      ],
                    ),
            ),
    );
  }

  /// Tablet-only: same sections, but the category bars flow into 2-3
  /// columns so the wider screen isn't one long stretched list.
  Widget _buildTabletBody(OfficerReportSummary? reports, double width) {
    final columns = tabletColumns(context, width);
    final categories = reports?.categories ?? const [];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screen),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Resolved',
                value: (reports?.resolved ?? 0).toString(),
                icon: Icons.task_alt_rounded,
                color: AppColors.resolvedText,
                backgroundColor: AppColors.greenTint,
              ),
            ),
            const SizedBox(width: AppSpacing.gap),
            Expanded(
              child: StatCard(
                label: 'Avg. Days',
                value:
                    reports?.averageResolutionDays?.toStringAsFixed(1) ?? '—',
                icon: Icons.timer_rounded,
                color: AppColors.inProgressText,
                backgroundColor: AppColors.blueTint,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.screen),
        const SectionTitle(title: 'Category-wise Resolution'),
        if (categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No report data available.')),
          )
        else
          for (var start = 0; start < categories.length; start += columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < start + columns; i++) ...[
                  if (i > start) const SizedBox(width: AppSpacing.gap),
                  Expanded(
                    child: i < categories.length
                        ? ReportRow(
                            label: categories[i].name,
                            value: '${(categories[i].percent * 100).round()}%',
                            percent: categories[i].percent,
                          )
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
        const SizedBox(height: AppSpacing.screen),
        const ExportPanel(),
      ],
    );
  }
}
