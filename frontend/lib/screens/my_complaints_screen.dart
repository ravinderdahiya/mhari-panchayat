import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint.dart';
import '../navigation/app_navigation.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/common_widgets.dart';
import '../widgets/complaint_widgets.dart';
import 'complaint_details_screen.dart';

enum _ComplaintFilter { all, active, inProgress, done, overdue }

class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({super.key});

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  _ComplaintFilter _filter = _ComplaintFilter.all;
  List<Complaint> _complaints = [];
  bool _loading = true;
  String? _error;

  static const _tabs = <(_ComplaintFilter, String)>[
    (_ComplaintFilter.all, 'All'),
    (_ComplaintFilter.active, 'Active'),
    (_ComplaintFilter.inProgress, 'In Progress'),
    (_ComplaintFilter.done, 'Done'),
    (_ComplaintFilter.overdue, 'Overdue'),
  ];

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
      final complaints = await ComplaintApi.getMine();
      if (!mounted) return;
      setState(() => _complaints = complaints);
    } on ComplaintApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Complaint> get _filtered {
    return _complaints.where(_matchesFilter).toList();
  }

  bool _matchesFilter(Complaint c) {
    return switch (_filter) {
      _ComplaintFilter.all => true,
      _ComplaintFilter.active =>
        complaintBucket(c.status) == ComplaintBucket.pending,
      _ComplaintFilter.inProgress =>
        complaintBucket(c.status) == ComplaintBucket.inProgress,
      _ComplaintFilter.done =>
        complaintBucket(c.status) == ComplaintBucket.resolved,
      _ComplaintFilter.overdue => _isOverdue(c),
    };
  }

  /// Open complaints older than 7 days are treated as overdue.
  bool _isOverdue(Complaint c) {
    final bucket = complaintBucket(c.status);
    if (bucket == ComplaintBucket.resolved ||
        bucket == ComplaintBucket.rejected) {
      return false;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final filed = DateTime(
      c.createdAt.year,
      c.createdAt.month,
      c.createdAt.day,
    );
    return today.difference(filed).inDays > 7;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _MyComplaintsHeader(),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: context.isTablet
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildContent(filtered, constraints.maxWidth),
                      )
                    : _buildContent(filtered, null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [tabletWidth] is null on phones (original single-column list). On
  /// tablets it is the available width: content is centred at
  /// [Breakpoints.wide] and the cards flow into 2-3 columns.
  Widget _buildContent(List<Complaint> filtered, double? tabletWidth) {
    final gutter = tabletWidth == null
        ? AppSpacing.screen
        : centeredGutter(
            tabletWidth,
            Breakpoints.wide,
            min: AppSpacing.screen,
          );
    final columns = tabletWidth == null
        ? 1
        : tabletColumns(context, tabletWidth);

    return Column(
      children: [
        const SizedBox(height: AppSpacing.screen),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: _tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (value, label) = _tabs[index];
              return _FilterPill(
                label: label,
                selected: _filter == value,
                onTap: () => setState(() => _filter = value),
              );
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _complaints.isEmpty
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: filtered.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.3,
                              child: Center(
                                child: Text(
                                  'No complaints in this filter',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: AppColors.mutedText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            AppSpacing.gap,
                            gutter,
                            AppSpacing.screen,
                          ),
                          // Tablets: one item per row of [columns] cards.
                          itemCount: (filtered.length / columns).ceil(),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.gap),
                          itemBuilder: (context, index) {
                            Widget card(Complaint complaint) =>
                                _MyComplaintCard(
                                  complaint: complaint,
                                  onTap: () => push(
                                    context,
                                    ComplaintDetailsScreen(
                                      complaint: complaint,
                                    ),
                                  ),
                                );
                            if (columns == 1) return card(filtered[index]);
                            final start = index * columns;
                            return _cardRow([
                              for (final complaint
                                  in filtered.skip(start).take(columns))
                                card(complaint),
                            ], columns);
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

/// Tablet-only: one row of [columns] equal-width, equal-height cells (a short
/// last row keeps its cells the same width as the rows above).
Widget _cardRow(List<Widget> cells, int columns) {
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < columns; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.gap),
          Expanded(child: i < cells.length ? cells[i] : const SizedBox()),
        ],
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Color(0xFF9E9E9E),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.mutedText,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.header : null,
            color: selected ? null : AppColors.greyBg,
            borderRadius: BorderRadius.circular(20),
            border: selected
                ? null
                : Border.all(color: AppColors.border, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF616161),
            ),
          ),
        ),
      ),
    );
  }
}

class _MyComplaintsHeader extends StatelessWidget {
  const _MyComplaintsHeader();

  @override
  Widget build(BuildContext context) {
    return GradientHeader(
      title: 'My Complaints',
      actions: defaultHeaderActions(context),
      tabletMaxWidth: Breakpoints.wide,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: GoogleFonts.poppins(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Search complaint ID or title',
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.22),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.gap),
            Material(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(AppRadius.button),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.filter_list_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyComplaintCard extends StatelessWidget {
  const _MyComplaintCard({required this.complaint, required this.onTap});

  final Complaint complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
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
                        color: const Color(0xFF212121),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ComplaintStatusRow(complaint: complaint),
                ],
              ),
              const SizedBox(height: 8),
              ComplaintAssetMetaRow(complaint: complaint),
              const SizedBox(height: 6),
              Text(
                complaint.displayCode,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
