import 'package:flutter/material.dart';

import '../models/complaint.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.screen),
                itemCount: _tasks.length,
                itemBuilder: (context, index) =>
                    ComplaintTile(complaint: _tasks[index], officerMode: true),
              ),
            ),
    );
  }
}
