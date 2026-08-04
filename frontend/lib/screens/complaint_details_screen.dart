import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/complaint_widgets.dart';
import '../widgets/photo_viewer.dart';

class ComplaintDetailsScreen extends StatefulWidget {
  const ComplaintDetailsScreen({super.key, required this.complaint});

  final Complaint complaint;

  @override
  State<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends State<ComplaintDetailsScreen> {
  late Complaint _complaint;
  bool _refreshing = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
    _refresh();
  }

  /// Re-fetches the complaint from the backend so this screen always shows
  /// the data actually stored on the server, not just what was submitted
  /// locally.
  Future<void> _refresh() async {
    try {
      final fresh = await ComplaintApi.getById(_complaint.id);
      if (!mounted) return;
      setState(() => _complaint = fresh);
    } catch (_) {
      // Keep the data we already have.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _verify(String status) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final updated = await ComplaintApi.updateStatus(
        _complaint.id,
        status: status,
      );
      if (!mounted) return;
      setState(() => _complaint = updated);
    } on ComplaintApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaint = _complaint;
    final timeline = _timelineStages(complaint);
    final needsVerification =
        complaint.status == ComplaintStatus.citizenVerification;

    return AppScaffold(
      title: complaint.displayCode,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.gap),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        complaint.displaySubject,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF212121),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ComplaintStatusRow(complaint: complaint),
                  ],
                ),
                const SizedBox(height: 10),
                ComplaintAssetMetaRow(complaint: complaint),
                const SizedBox(height: AppSpacing.screen),
                if (complaint.photoUrls.isNotEmpty) ...[
                  Text(
                    'Complaint Photos',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PhotoThumbRow(urls: complaint.photoUrls),
                  const SizedBox(height: AppSpacing.screen),
                ],
                if (complaint.resolutionPhotoUrls.isNotEmpty) ...[
                  Text(
                    'Officer Resolution Photos',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Photos taken by the officer after fixing the issue',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PhotoThumbRow(urls: complaint.resolutionPhotoUrls),
                  const SizedBox(height: AppSpacing.screen),
                ],
                Text(
                  'Description',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  complaint.description,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    height: 1.5,
                    color: const Color(0xFF424242),
                  ),
                ),
                if (needsVerification) ...[
                  const SizedBox(height: AppSpacing.screen),
                  _VerificationCard(
                    submitting: _submitting,
                    onConfirm: () => _verify('CLOSED'),
                    onReopen: () => _verify('WORK_STARTED'),
                  ),
                ],
                const SizedBox(height: AppSpacing.screen),
                Text(
                  'Timeline',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (var i = 0; i < timeline.length; i++)
                          _TimelineStage(
                            title: timeline[i].title,
                            done: timeline[i].done,
                            isLast: i == timeline.length - 1,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _OfficerFooter(name: complaint.assignedOfficerName),
        ],
      ),
    );
  }

  List<_TimelineData> _timelineStages(Complaint complaint) {
    const order = [
      ComplaintStatus.pending,
      ComplaintStatus.assigned,
      ComplaintStatus.accepted,
      ComplaintStatus.inspection,
      ComplaintStatus.workStarted,
      ComplaintStatus.citizenVerification,
      ComplaintStatus.closed,
    ];

    if (complaint.status == ComplaintStatus.rejected) {
      return const [
        _TimelineData(title: 'Registered', done: true),
        _TimelineData(title: 'Rejected', done: true),
      ];
    }

    final currentIndex = order.indexOf(complaint.status);
    return [
      for (var i = 0; i < order.length; i++)
        _TimelineData(title: statusLabel(order[i]), done: i <= currentIndex),
    ];
  }
}

class _PhotoThumbRow extends StatelessWidget {
  const _PhotoThumbRow({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in urls)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: InkWell(
              onTap: () => showPhotoViewer(context, imageUrl: url),
              child: Image.network(
                url,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
          ),
      ],
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.submitting,
    required this.onConfirm,
    required this.onReopen,
  });

  final bool submitting;
  final VoidCallback onConfirm;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The officer marked this complaint as resolved',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Please confirm whether the issue has actually been fixed.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: submitting ? null : onReopen,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.rejectedText,
                    side: const BorderSide(color: AppColors.rejectedText),
                  ),
                  child: const Text('Not Fixed, Reopen'),
                ),
              ),
              const SizedBox(width: AppSpacing.gap),
              Expanded(
                child: GradientButton(
                  onPressed: submitting ? null : onConfirm,
                  label: 'Confirm Resolved',
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineData {
  const _TimelineData({required this.title, required this.done});

  final String title;
  final bool done;
}

class _TimelineStage extends StatelessWidget {
  const _TimelineStage({
    required this.title,
    required this.done,
    required this.isLast,
  });

  final String title;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dotColor = done ? AppColors.secondary : const Color(0xFFBDBDBD);
    final lineColor = done ? AppColors.greenTint : AppColors.greyBg;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: done ? AppColors.greenTint : AppColors.greyBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: done
                      ? const Color(0xFF212121)
                      : const Color(0xFF757575),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerFooter extends StatelessWidget {
  const _OfficerFooter({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final displayName = name ?? 'Not assigned';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screen,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.orangeTint,
            child: Text(
              name != null ? name![0].toUpperCase() : '?',
              style: GoogleFonts.poppins(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name != null ? 'Field Officer' : 'Awaiting assignment',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF757575),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
