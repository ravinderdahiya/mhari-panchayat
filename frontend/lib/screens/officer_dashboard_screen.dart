import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../navigation/app_navigation.dart';
import '../services/auth_service.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/complaint_widgets.dart';
import 'notification_screen.dart';
import 'officer_action_screen.dart';

class OfficerDashboardScreen extends StatefulWidget {
  const OfficerDashboardScreen({super.key});

  @override
  State<OfficerDashboardScreen> createState() => _OfficerDashboardScreenState();
}

class _OfficerDashboardScreenState extends State<OfficerDashboardScreen> {
  List<Complaint> _complaints = const [];
  bool _loading = true;
  Position? _myPosition;
  String? _officerName;
  String? _officerProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSession();
      _loadComplaints();
      _loadMyPosition();
    });
  }

  Future<void> _loadSession() async {
    final session = await AuthService.getSession();
    if (!mounted) return;
    setState(() {
      _officerName = session?.officerName;
      _officerProfileId = session?.officerProfileId;
    });
  }

  Future<void> _loadComplaints() async {
    setState(() => _loading = true);
    try {
      final complaints = await ComplaintApi.getOfficerQueue();
      if (!mounted) return;
      setState(() => _complaints = complaints);
    } on ComplaintApiException catch (_) {
      // Keep showing an empty list if the queue can't be loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMyPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() => _myPosition = position);
    } catch (_) {
      // Distance labels just fall back to '' if location can't be read.
    }
  }

  String _distanceLabel(Complaint complaint) {
    final myPosition = _myPosition;
    if (myPosition == null ||
        complaint.latitude == null ||
        complaint.longitude == null) {
      return '';
    }
    final meters = Geolocator.distanceBetween(
      myPosition.latitude,
      myPosition.longitude,
      complaint.latitude!,
      complaint.longitude!,
    );
    return meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km away'
        : '${meters.round()} m away';
  }

  Future<void> _takeComplaint(Complaint complaint) async {
    final officerProfileId = _officerProfileId;
    if (officerProfileId == null) return;
    try {
      await ComplaintApi.assign(complaint.id, officerProfileId);
      if (!mounted) return;
      _loadComplaints();
    } on ComplaintApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _complaints
        .where((c) => complaintBucket(c.status) == ComplaintBucket.pending)
        .length;
    final active = _complaints
        .where((c) => complaintBucket(c.status) == ComplaintBucket.inProgress)
        .length;
    final completed = _complaints
        .where((c) => complaintBucket(c.status) == ComplaintBucket.resolved)
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _OfficerHeader(
            designation: _officerName ?? 'Field Officer',
            onNotificationTap: () => push(context, const NotificationScreen()),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadComplaints,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screen,
                            AppSpacing.screen + 4,
                            AppSpacing.screen,
                            AppSpacing.screen,
                          ),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _OfficerStat(
                                    label: 'Pending',
                                    value: pending.toString().padLeft(2, '0'),
                                    icon: Icons.hourglass_empty_rounded,
                                    color: AppColors.pendingText,
                                    background: AppColors.orangeTint,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.gap),
                                Expanded(
                                  child: _OfficerStat(
                                    label: 'Active',
                                    value: active.toString().padLeft(2, '0'),
                                    icon: Icons.assignment_rounded,
                                    color: AppColors.inProgressText,
                                    background: AppColors.blueTint,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.gap),
                                Expanded(
                                  child: _OfficerStat(
                                    label: 'Completed',
                                    value: completed.toString().padLeft(2, '0'),
                                    icon: Icons.task_alt_rounded,
                                    color: AppColors.resolvedText,
                                    background: AppColors.greenTint,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.screen),
                            Text(
                              'Complaint Queue',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF212121),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.gap),
                            if (_complaints.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Center(
                                  child: Text(
                                    'No complaints yet',
                                    style: GoogleFonts.poppins(
                                      color: AppColors.mutedText,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ..._complaints.map(
                                (complaint) => _OfficerTaskCard(
                                  complaint: complaint,
                                  distance: _distanceLabel(complaint),
                                  onAction: () async {
                                    if (complaint.status ==
                                        ComplaintStatus.pending) {
                                      await _takeComplaint(complaint);
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => OfficerActionScreen(
                                          complaint: complaint,
                                        ),
                                      ),
                                    );
                                    if (context.mounted) _loadComplaints();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerHeader extends StatelessWidget {
  const _OfficerHeader({
    required this.designation,
    required this.onNotificationTap,
  });

  final String designation;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        topPadding + 12,
        AppSpacing.screen,
        28,
      ),
      decoration: const BoxDecoration(gradient: AppGradients.header),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'नमस्ते 👋',
                  style: GoogleFonts.notoSansDevanagari(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  designation,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFFF3E0),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNotificationTap,
            icon: const Icon(Icons.notifications_rounded, color: Colors.white),
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerStat extends StatelessWidget {
  const _OfficerStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF616161),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerTaskCard extends StatelessWidget {
  const _OfficerTaskCard({
    required this.complaint,
    required this.distance,
    required this.onAction,
  });

  final Complaint complaint;
  final String distance;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final isPending = complaint.status == ComplaintStatus.pending;
    final actionLabel = isPending ? 'Accept' : 'Open';
    final actionIcon = isPending
        ? Icons.check_rounded
        : Icons.chevron_right_rounded;
    final locationLabel = distance.isEmpty
        ? complaint.village
        : '${complaint.village} · $distance';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    complaint.displaySubject,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(status: complaint.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              complaint.locationLabel,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.mutedText,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.near_me_rounded,
                  size: 15,
                  color: Color(0xFF9E9E9E),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    locationLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF757575),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                onPressed: onAction,
                label: actionLabel,
                icon: actionIcon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
