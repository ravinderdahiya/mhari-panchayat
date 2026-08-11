import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_notification.dart';
import '../services/complaint_api.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../navigation/app_navigation.dart';
import '../widgets/common_widgets.dart';
import 'complaint_details_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotification> _notifications = const [];

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
      final notifications = await NotificationApi.getMine();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    } on NotificationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'सूचनाएं लोड नहीं हो पाईं। पुनः प्रयास करें।';
        _loading = false;
      });
    }
  }

  Future<void> _openNotification(AppNotification item, int index) async {
    if (!item.isRead) {
      setState(() {
        _notifications = [
          for (var i = 0; i < _notifications.length; i++)
            if (i == index) item.copyWith(isRead: true) else _notifications[i],
        ];
      });
      try {
        await NotificationApi.markRead(item.id);
      } catch (_) {
        // Keep UI optimistic; next refresh will sync.
      }
    }

    if (item.complaintId.isEmpty || !mounted) return;

    try {
      final complaint = await ComplaintApi.getById(item.complaintId);
      if (!mounted) return;
      await push(context, ComplaintDetailsScreen(complaint: complaint));
    } on ComplaintApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint खोल नहीं पाए।')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientHeader(
            title: 'Notifications',
            onBack: widget.showBackButton
                ? () => Navigator.of(context).maybePop()
                : null,
            actions: defaultHeaderActions(context),
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
                child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.secondaryText,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _load,
              child: const Text('पुनः प्रयास करें'),
            ),
          ),
        ],
      );
    }
    if (_notifications.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.notifications_none_rounded,
            size: 40,
            color: AppColors.secondaryText,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'कोई सूचना नहीं',
              style: GoogleFonts.poppins(color: AppColors.secondaryText),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 72,
        color: AppColors.border,
      ),
      itemBuilder: (context, index) {
        final item = _notifications[index];
        return _NotifRow(
          item: item,
          onTap: () => _openNotification(item, index),
        );
      },
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  ({Color bg, Color fg, IconData icon}) get _style {
    switch (item.kind) {
      case NotificationKind.resolved:
        return (
          bg: AppColors.greenTint,
          fg: AppColors.resolvedText,
          icon: Icons.check_circle_rounded,
        );
      case NotificationKind.assigned:
        return (
          bg: AppColors.blueTint,
          fg: AppColors.inProgressText,
          icon: Icons.assignment_ind_rounded,
        );
      case NotificationKind.submitted:
        return (
          bg: AppColors.orangeTint,
          fg: AppColors.pendingText,
          icon: Icons.mark_email_unread_rounded,
        );
      case NotificationKind.rejected:
        return (
          bg: AppColors.rejectedBg,
          fg: AppColors.rejectedText,
          icon: Icons.cancel_rounded,
        );
    }
  }

  String get _relativeTime {
    final date = item.createdAt;
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final day = date.day.toString().padLeft(2, '0');
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
    return '$day ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: item.isRead ? null : const Color(0x14E65100),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screen,
          vertical: 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: style.bg,
              foregroundColor: style.fg,
              child: Icon(style.icon, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight:
                          item.isRead ? FontWeight.w600 : FontWeight.w700,
                      color: const Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.message,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFF616161),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _relativeTime,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),
            if (!item.isRead)
              Container(
                margin: const EdgeInsets.only(top: 6, left: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFE65100),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
