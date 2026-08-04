import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../navigation/app_navigation.dart';
import '../screens/complaint_details_screen.dart';
import '../screens/officer_action_screen.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// Broad grouping used for coloring/filtering — the pipeline itself has 9
/// exact statuses, but map legends / stat tiles read better bucketed.
enum ComplaintBucket { pending, inProgress, resolved, rejected }

ComplaintBucket complaintBucket(ComplaintStatus status) {
  return switch (status) {
    ComplaintStatus.pending ||
    ComplaintStatus.assigned => ComplaintBucket.pending,
    ComplaintStatus.accepted ||
    ComplaintStatus.inspection ||
    ComplaintStatus.workStarted ||
    ComplaintStatus.citizenVerification => ComplaintBucket.inProgress,
    ComplaintStatus.resolved ||
    ComplaintStatus.closed => ComplaintBucket.resolved,
    ComplaintStatus.rejected => ComplaintBucket.rejected,
  };
}

/// Village/GP label for a complaint (asset-derived, since complaints no
/// longer store location fields of their own).
String complaintAssetLocationLabel(Complaint complaint) {
  return complaint.locationLabel;
}

class ComplaintTile extends StatelessWidget {
  const ComplaintTile({
    super.key,
    required this.complaint,
    this.officerMode = false,
  });

  final Complaint complaint;
  final bool officerMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: statusBackgroundColor(complaint.status),
          foregroundColor: statusTextColor(complaint.status),
          child: const Icon(Icons.report_rounded),
        ),
        title: Text(complaint.displaySubject),
        subtitle: Text('${complaint.displayCode} · ${complaint.village}'),
        trailing: StatusChip(status: complaint.status),
        onTap: () => push(
          context,
          officerMode
              ? OfficerActionScreen(complaint: complaint)
              : ComplaintDetailsScreen(complaint: complaint),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final ComplaintStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusBackgroundColor(status),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: statusTextColor(status),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Status chip row for a complaint.
class ComplaintStatusRow extends StatelessWidget {
  const ComplaintStatusRow({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    return StatusChip(status: complaint.status);
  }
}

/// Compact tagged meta row: asset name, location, date (no complainant name).
class ComplaintAssetMetaRow extends StatelessWidget {
  const ComplaintAssetMetaRow({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[
      if (complaint.assetType?.isNotEmpty ?? false)
        _MetaTag(icon: Icons.apartment_outlined, label: complaint.assetType!),
      if (complaint.department?.isNotEmpty ?? false)
        _MetaTag(
          icon: Icons.account_balance_outlined,
          label: complaint.department!,
        ),
      if (complaint.priority?.isNotEmpty ?? false)
        _MetaTag(icon: Icons.flag_outlined, label: complaint.priority!),
      _MetaTag(
        icon: Icons.location_on_outlined,
        label: complaintAssetLocationLabel(complaint),
      ),
      _MetaTag(icon: Icons.calendar_today_outlined, label: complaint.dateLabel),
    ];

    return Wrap(spacing: 10, runSpacing: 6, children: tags);
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF757575)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF616161),
          ),
        ),
      ],
    );
  }
}

class SearchAndFilterBar extends StatelessWidget {
  const SearchAndFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search complaint ID',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.gap),
        IconButton.filledTonal(
          onPressed: () {},
          style: IconButton.styleFrom(
            backgroundColor: AppColors.orangeTint,
            foregroundColor: AppColors.primary,
          ),
          icon: const Icon(Icons.filter_list_rounded),
          tooltip: 'Filter',
        ),
      ],
    );
  }
}

class PhotoPreviewGrid extends StatelessWidget {
  const PhotoPreviewGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: EvidenceBox(
            label: 'Before Photo',
            icon: Icons.photo_camera_rounded,
          ),
        ),
        SizedBox(width: AppSpacing.gap),
        Expanded(
          child: EvidenceBox(
            label: 'After Photo',
            icon: Icons.add_photo_alternate_rounded,
          ),
        ),
      ],
    );
  }
}

class EvidenceBox extends StatelessWidget {
  const EvidenceBox({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: AppColors.secondary),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Text('Geo-tagged'),
        ],
      ),
    );
  }
}

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.done,
  });

  final String title;
  final String subtitle;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        done
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: done ? AppColors.secondary : const Color(0xFFBDBDBD),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class ComplaintSummaryCard extends StatelessWidget {
  const ComplaintSummaryCard({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final location = complaint.latitude != null && complaint.longitude != null
        ? '${complaint.latitude}, ${complaint.longitude}'
        : '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              complaint.displayCode,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DetailRow(label: 'Issue', value: complaint.category ?? 'General'),
            DetailRow(label: 'Village', value: complaint.village),
            DetailRow(label: 'Location', value: location),
            Text(complaint.description),
          ],
        ),
      ),
    );
  }
}

Color statusTextColor(ComplaintStatus status) {
  return switch (complaintBucket(status)) {
    ComplaintBucket.pending => AppColors.pendingText,
    ComplaintBucket.inProgress => AppColors.inProgressText,
    ComplaintBucket.resolved => AppColors.resolvedText,
    ComplaintBucket.rejected => AppColors.rejectedText,
  };
}

Color statusBackgroundColor(ComplaintStatus status) {
  return switch (complaintBucket(status)) {
    ComplaintBucket.pending => AppColors.pendingBg,
    ComplaintBucket.inProgress => AppColors.inProgressBg,
    ComplaintBucket.resolved => AppColors.resolvedBg,
    ComplaintBucket.rejected => AppColors.rejectedBg,
  };
}

// Kept for map pin coloring and any legacy usage.
Color statusColor(ComplaintStatus status) => statusTextColor(status);

String statusLabel(ComplaintStatus status) {
  return switch (status) {
    ComplaintStatus.pending => 'Pending',
    ComplaintStatus.assigned => 'Assigned',
    ComplaintStatus.accepted => 'Accepted',
    ComplaintStatus.inspection => 'Inspection',
    ComplaintStatus.workStarted => 'Work Started',
    ComplaintStatus.resolved => 'Resolved',
    ComplaintStatus.citizenVerification => 'Awaiting Confirmation',
    ComplaintStatus.closed => 'Closed',
    ComplaintStatus.rejected => 'Rejected',
  };
}
