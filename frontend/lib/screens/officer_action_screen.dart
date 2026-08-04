import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/complaint.dart';
import '../models/officer_summary.dart';
import '../services/complaint_api.dart';
import '../services/officer_api.dart';
import '../theme/app_theme.dart';
import '../utils/photo_stamp.dart';
import '../widgets/common_widgets.dart';
import '../widgets/complaint_widgets.dart';
import '../widgets/photo_viewer.dart';

class _NextAction {
  const _NextAction({
    required this.label,
    required this.status,
    this.destructive = false,
    this.needsReason = false,
    this.needsPhoto = false,
  });

  final String label;
  final String status;
  final bool destructive;
  final bool needsReason;
  final bool needsPhoto;
}

/// Legal next steps an officer can take, keyed by the complaint's current
/// status — mirrors the backend's transition table exactly.
const Map<ComplaintStatus, List<_NextAction>> _officerActions = {
  ComplaintStatus.assigned: [
    _NextAction(label: 'Accept', status: 'ACCEPTED'),
    _NextAction(
      label: 'Reject',
      status: 'REJECTED',
      destructive: true,
      needsReason: true,
    ),
  ],
  ComplaintStatus.accepted: [
    _NextAction(label: 'Start Inspection', status: 'INSPECTION'),
  ],
  ComplaintStatus.inspection: [
    _NextAction(label: 'Start Work', status: 'WORK_STARTED'),
    _NextAction(
      label: 'Reject',
      status: 'REJECTED',
      destructive: true,
      needsReason: true,
    ),
  ],
  ComplaintStatus.workStarted: [
    _NextAction(label: 'Mark Resolved', status: 'RESOLVED', needsPhoto: true),
  ],
};

class OfficerActionScreen extends StatefulWidget {
  const OfficerActionScreen({super.key, required this.complaint});

  final Complaint complaint;

  @override
  State<OfficerActionScreen> createState() => _OfficerActionScreenState();
}

class _OfficerActionScreenState extends State<OfficerActionScreen> {
  final _remarksController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<Uint8List> _resolutionPhotos = [];
  late Complaint _complaint;
  bool _submitting = false;
  bool _reassigning = false;

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _addResolutionPhoto() async {
    if (_resolutionPhotos.length >= 5) {
      _showMessage('Maximum 5 resolution photos allowed');
      return;
    }
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null) return;
      var bytes = await photo.readAsBytes();

      final lat = _complaint.latitude;
      final lng = _complaint.longitude;
      if (lat != null && lng != null) {
        try {
          bytes = await PhotoStamp.stamp(
            bytes: bytes,
            latitude: lat,
            longitude: lng,
          );
        } catch (_) {
          // Keep the unstamped photo if overlay rendering fails.
        }
      }

      if (!mounted) return;
      setState(() => _resolutionPhotos.add(bytes));
    } catch (_) {
      _showMessage('Could not capture photo. Check camera permission.');
    }
  }

  Future<void> _performAction(_NextAction action) async {
    if (_submitting) return;
    if (action.needsReason && _remarksController.text.trim().isEmpty) {
      _showMessage('Please add a reason before rejecting');
      return;
    }
    if (action.needsPhoto && _resolutionPhotos.isEmpty) {
      _showMessage('Please add at least one after-fix photo');
      return;
    }

    setState(() => _submitting = true);
    try {
      final updated = await ComplaintApi.updateStatus(
        _complaint.id,
        status: action.status,
        reason: _remarksController.text.trim(),
        resolutionPhotos: action.needsPhoto ? _resolutionPhotos : const [],
      );
      if (!mounted) return;
      if (action.status == 'RESOLVED' ||
          _officerActions[updated.status] == null) {
        Navigator.of(context).pop();
      } else {
        setState(() => _complaint = updated);
      }
    } on ComplaintApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reassign() async {
    if (_reassigning) return;
    setState(() => _reassigning = true);
    List<OfficerSummary> officers;
    try {
      officers = await OfficerApi.getOfficers();
    } on OfficerApiException catch (e) {
      setState(() => _reassigning = false);
      _showMessage(e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _reassigning = false);

    final selected = await showDialog<OfficerSummary>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign to officer'),
        children: [
          for (final officer in officers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(officer),
              child: Text('${officer.name} (${officer.staffId})'),
            ),
        ],
      ),
    );
    if (selected == null) return;

    try {
      final updated = await ComplaintApi.assign(_complaint.id, selected.id);
      if (!mounted) return;
      setState(() => _complaint = updated);
      _showMessage('Assigned to ${selected.name}');
    } on ComplaintApiException catch (e) {
      _showMessage(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaint = _complaint;
    final actions = _officerActions[complaint.status] ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradientAppBar(
        title: '${complaint.displayCode} · Action',
        actions: [
          IconButton(
            onPressed: _reassigning ? null : _reassign,
            tooltip: 'Assign to officer',
            icon: _reassigning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  complaint.displaySubject,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusChip(status: complaint.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            complaint.locationLabel,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: AppSpacing.screen),
          _CitizenInfoCard(
            phone: complaint.citizenMobile ?? 'Not available',
            address: '${complaint.village}, ${complaint.panchayat}',
          ),
          if (complaint.assignedOfficerName != null) ...[
            const SizedBox(height: AppSpacing.gap),
            _AssignedOfficerRow(name: complaint.assignedOfficerName!),
          ],
          const SizedBox(height: AppSpacing.screen),
          _SectionLabel('Description'),
          const SizedBox(height: AppSpacing.gap),
          Text(
            complaint.description,
            style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
          ),
          if (complaint.photoUrls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.screen),
            _SectionLabel('Complaint Photos'),
            const SizedBox(height: AppSpacing.gap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in complaint.photoUrls)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => showPhotoViewer(context, imageUrl: url),
                      child: Image.network(
                        url,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (complaint.resolutionPhotoUrls.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.screen),
            _SectionLabel('Resolution Photos'),
            const SizedBox(height: AppSpacing.gap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in complaint.resolutionPhotoUrls)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => showPhotoViewer(context, imageUrl: url),
                      child: Image.network(
                        url,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (actions.any((a) => a.needsPhoto)) ...[
            const SizedBox(height: AppSpacing.screen),
            _SectionLabel('After-fix Photos'),
            const SizedBox(height: 4),
            Text(
              'Capture photos of the fixed work before marking resolved.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.mutedText,
              ),
            ),
            const SizedBox(height: AppSpacing.gap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _resolutionPhotos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          _resolutionPhotos[i],
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _resolutionPhotos.removeAt(i)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_resolutionPhotos.length < 5)
                  InkWell(
                    onTap: _addResolutionPhoto,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.greenTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.add_a_photo_rounded,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.screen),
            _SectionLabel('Remarks'),
            const SizedBox(height: AppSpacing.gap),
            TextField(
              controller: _remarksController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Add resolution remarks or reason for rejection...',
                alignLabelWithHint: true,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.screen),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.greyBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _readOnlyMessage(complaint.status),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.mutedText,
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: actions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.gap),
                      Expanded(
                        child: actions[i].destructive
                            ? OutlinedButton.icon(
                                onPressed: _submitting
                                    ? null
                                    : () => _performAction(actions[i]),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.rejectedText,
                                  side: const BorderSide(
                                    color: AppColors.rejectedText,
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: Text(actions[i].label),
                              )
                            : GradientButton(
                                onPressed: _submitting
                                    ? null
                                    : () => _performAction(actions[i]),
                                label: _submitting
                                    ? 'Saving...'
                                    : actions[i].label,
                                icon: Icons.check_rounded,
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  String _readOnlyMessage(ComplaintStatus status) {
    return switch (status) {
      ComplaintStatus.pending => 'Not yet assigned.',
      ComplaintStatus.citizenVerification =>
        'Waiting for the citizen to confirm the resolution.',
      ComplaintStatus.closed => 'This complaint is closed.',
      ComplaintStatus.rejected => 'This complaint was rejected.',
      _ => 'No action available right now.',
    };
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF212121),
      ),
    );
  }
}

class _AssignedOfficerRow extends StatelessWidget {
  const _AssignedOfficerRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blueTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.badge_rounded,
            size: 18,
            color: AppColors.inProgressText,
          ),
          const SizedBox(width: 8),
          Text(
            'Assigned to: $name',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.inProgressText,
            ),
          ),
        ],
      ),
    );
  }
}

class _CitizenInfoCard extends StatelessWidget {
  const _CitizenInfoCard({required this.phone, required this.address});

  final String phone;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.orangeTint,
              foregroundColor: AppColors.primary,
              child: Icon(Icons.person_rounded, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'नागरिक',
                    style: GoogleFonts.notoSansDevanagari(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _InfoLine(icon: Icons.phone_rounded, text: phone),
                  const SizedBox(height: 2),
                  _InfoLine(icon: Icons.location_on_rounded, text: address),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF616161),
            ),
          ),
        ),
      ],
    );
  }
}
