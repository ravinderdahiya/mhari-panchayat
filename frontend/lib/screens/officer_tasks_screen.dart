import 'package:flutter/material.dart';

import '../models/complaint.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/common_widgets.dart';
import '../widgets/complaint_widgets.dart';

class OfficerTasksScreen extends StatefulWidget {
  const OfficerTasksScreen({super.key});

  @override
  State<OfficerTasksScreen> createState() => _OfficerTasksScreenState();
}

class _OfficerTasksScreenState extends State<OfficerTasksScreen> {
  List<Complaint> _tasks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final complaints = await ComplaintApi.getOfficerQueue();
      if (!mounted) return;
      setState(() {
        _tasks = complaints
            .where((c) => complaintBucket(c.status) != ComplaintBucket.resolved)
            .toList();
      });
    } on ComplaintApiException catch (_) {
      // Keep showing an empty list if the queue can't be loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'My Tasks',
      showBackButton: false,
      tabletMaxWidth: Breakpoints.wide,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: context.isTablet
                  ? LayoutBuilder(
                      builder: (context, constraints) =>
                          _buildTabletGrid(constraints.maxWidth),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.screen),
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) => ComplaintTile(
                        complaint: _tasks[index],
                        officerMode: true,
                      ),
                    ),
            ),
    );
  }

  /// Tablet-only: task tiles in rows of 2-3 equal-width columns.
  Widget _buildTabletGrid(double width) {
    final columns = tabletColumns(context, width);
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.screen),
      itemCount: (_tasks.length / columns).ceil(),
      itemBuilder: (context, index) {
        final start = index * columns;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.gap),
              Expanded(
                child: start + i < _tasks.length
                    ? ComplaintTile(
                        complaint: _tasks[start + i],
                        officerMode: true,
                      )
                    : const SizedBox(),
              ),
            ],
          ],
        );
      },
    );
  }
}
