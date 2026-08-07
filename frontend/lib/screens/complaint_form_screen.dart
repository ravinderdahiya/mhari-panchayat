import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint_category_option.dart';
import '../models/complaint_form_option.dart';
import '../models/asset_type.dart';
import '../models/survey_department.dart';
import '../services/asset_type_api.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../utils/photo_stamp.dart';
import '../widgets/common_widgets.dart';
import '../widgets/in_app_camera.dart';
import '../widgets/photo_viewer.dart';
import 'complaint_success_screen.dart';

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({
    super.key,
    required this.location,
    required this.categories,
    required this.priorities,
    this.latitude,
    this.longitude,
  });

  final ComplaintLocationSelection location;
  final List<ComplaintCategoryOption> categories;
  final List<ComplaintPriorityOption> priorities;
  final double? latitude;
  final double? longitude;

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  int? _departmentId;
  int? _assetTypeId;
  int? _categoryId;
  int? _priorityId;
  final _descriptionController = TextEditingController();
  final List<Uint8List> _photos = [];
  static const _maxPhotos = 5;
  bool _submitting = false;
  bool _loadingDepartments = true;
  bool _loadingAssets = false;
  String? _masterError;
  List<SurveyDepartment> _departments = const [];
  List<AssetType> _assetTypes = const [];

  @override
  void initState() {
    super.initState();
    if (widget.priorities.isNotEmpty) {
      final mediumIndex = widget.priorities.indexWhere(
        (item) => item.name.toLowerCase() == 'medium',
      );
      _priorityId = mediumIndex >= 0
          ? widget.priorities[mediumIndex].id
          : widget.priorities.first.id;
    }
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loadingDepartments = true;
      _masterError = null;
    });
    try {
      final departments = await AssetTypeApi.getDepartments();
      if (!mounted) return;
      setState(() => _departments = departments);
    } on AssetTypeApiException catch (e) {
      if (!mounted) return;
      setState(() => _masterError = e.message);
    } finally {
      if (mounted) setState(() => _loadingDepartments = false);
    }
  }

  Future<void> _selectDepartment(int? departmentId) async {
    setState(() {
      _departmentId = departmentId;
      _assetTypeId = null;
      _assetTypes = const [];
      _masterError = null;
    });
    if (departmentId == null) return;

    setState(() => _loadingAssets = true);
    try {
      final assets = await AssetTypeApi.getAssetTypes(
        departmentId: departmentId,
      );
      if (!mounted || _departmentId != departmentId) return;
      setState(() => _assetTypes = assets);
    } on AssetTypeApiException catch (e) {
      if (!mounted) return;
      setState(() => _masterError = e.message);
    } finally {
      if (mounted && _departmentId == departmentId) {
        setState(() => _loadingAssets = false);
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= _maxPhotos) {
      _showMessage('Maximum $_maxPhotos issue photos allowed');
      return;
    }
    try {
      final captured = await InAppCamera.capture(context);
      if (captured == null) return;
      var bytes = captured;
      if (widget.latitude != null && widget.longitude != null) {
        try {
          bytes = await PhotoStamp.stamp(
            bytes: bytes,
            latitude: widget.latitude!,
            longitude: widget.longitude!,
          );
        } catch (_) {
          // A usable photo is still kept if stamping fails.
        }
      }
      if (!mounted) return;
      setState(() => _photos.add(bytes));
    } catch (_) {
      _showMessage(
        'Photo could not be captured. Please check camera permission.',
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final description = _descriptionController.text.trim();
    if (_departmentId == null) {
      _showMessage('Please select a department');
      return;
    }
    if (_assetTypeId == null) {
      _showMessage('Please select an asset');
      return;
    }
    if (_categoryId == null) {
      _showMessage('Please select a complaint category');
      return;
    }
    if (_priorityId == null) {
      _showMessage('Please select priority');
      return;
    }
    if (description.length < 10) {
      _showMessage('Please describe the issue in at least 10 characters');
      return;
    }
    if (_photos.isEmpty) {
      _showMessage('Please take at least one photo of the issue');
      return;
    }

    setState(() => _submitting = true);
    try {
      final complaint = await ComplaintApi.submit(
        departmentId: _departmentId!,
        assetTypeId: _assetTypeId!,
        districtId: widget.location.district.id,
        tehsilId: widget.location.tehsil.id,
        villageId: widget.location.village.id,
        categoryId: _categoryId!,
        priorityId: _priorityId!,
        description: description,
        latitude: widget.latitude,
        longitude: widget.longitude,
        photos: List<Uint8List>.from(_photos),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ComplaintSuccessScreen(complaint: complaint),
        ),
      );
    } on ComplaintApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'New Complaint',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screen),
              children: [
                _ReadOnlyLocationFields(
                  location: widget.location,
                  latitude: widget.latitude,
                  longitude: widget.longitude,
                ),
                const SizedBox(height: AppSpacing.screen),
                const _SectionHeader(
                  title: 'Choose department and asset',
                  subtitle: 'Select who should receive this complaint.',
                ),
                const SizedBox(height: 12),
                if (_loadingDepartments)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  DropdownButtonFormField<int>(
                    initialValue: _departmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Department *',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    items: [
                      for (final department in _departments)
                        DropdownMenuItem(
                          value: department.id,
                          child: Text(
                            department.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _selectDepartment,
                  ),
                const SizedBox(height: AppSpacing.gap),
                DropdownButtonFormField<int>(
                  key: ValueKey('asset-$_departmentId-$_assetTypeId'),
                  initialValue: _assetTypeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Asset *',
                    prefixIcon: const Icon(Icons.apartment_outlined),
                    suffixIcon: _loadingAssets
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  items: [
                    for (final asset in _assetTypes)
                      if (int.tryParse(asset.id) case final id?)
                        DropdownMenuItem(value: id, child: Text(asset.name)),
                  ],
                  onChanged: _loadingAssets || _assetTypes.isEmpty
                      ? null
                      : (value) => setState(() => _assetTypeId = value),
                ),
                if (_masterError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _masterError!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.rejectedText,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.gap),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Complaint category *',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final category in widget.categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: AppSpacing.screen),
                const Divider(),
                const SizedBox(height: AppSpacing.gap),
                const _SectionHeader(
                  title: 'Add details',
                  subtitle: 'Add description, priority and a clear photo.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _priorityId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Priority *',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: [
                    for (final priority in widget.priorities)
                      DropdownMenuItem(
                        value: priority.id,
                        child: Text(priority.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _priorityId = value),
                ),
                const SizedBox(height: AppSpacing.gap),
                TextField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 2000,
                  style: GoogleFonts.poppins(),
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    hintText: 'Describe the issue and exact spot…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.gap),
                Text(
                  'Issue photos * (up to $_maxPhotos)',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _PhotoInput(
                  photos: _photos,
                  maxPhotos: _maxPhotos,
                  onTakePhoto: _takePhoto,
                  onRemove: (index) => setState(() => _photos.removeAt(index)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.gapSm,
              AppSpacing.screen,
              AppSpacing.screen,
            ),
            child: GradientButton(
              onPressed: _submitting ? null : _submit,
              label: _submitting ? 'Submitting…' : 'Submit complaint',
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyLocationFields extends StatelessWidget {
  const _ReadOnlyLocationFields({
    required this.location,
    required this.latitude,
    required this.longitude,
  });

  final ComplaintLocationSelection location;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final panchayat = location.village.panchayatName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.my_location_rounded,
              size: 19,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'GPS location (read-only)',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.mutedText,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'These details are filled automatically from your current location and cannot be edited.',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.mutedText),
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'District',
          value: location.district.name,
          icon: Icons.map_outlined,
        ),
        const SizedBox(height: AppSpacing.gap),
        _ReadOnlyField(
          label: 'Tehsil / Sub-Tehsil',
          value: location.tehsil.name,
          icon: Icons.location_city_outlined,
        ),
        const SizedBox(height: AppSpacing.gap),
        _ReadOnlyField(
          label: 'Village',
          value: location.village.name,
          icon: Icons.holiday_village_outlined,
        ),
        const SizedBox(height: AppSpacing.gap),
        _ReadOnlyField(
          label: 'Panchayat',
          value: panchayat.isEmpty ? 'Not available' : panchayat,
          icon: Icons.account_balance_outlined,
        ),
        const SizedBox(height: AppSpacing.gap),
        Row(
          children: [
            Expanded(
              child: _ReadOnlyField(
                label: 'GPS Latitude',
                value: latitude?.toStringAsFixed(6) ?? 'Not available',
                icon: Icons.gps_fixed_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.gap),
            Expanded(
              child: _ReadOnlyField(
                label: 'GPS Longitude',
                value: longitude?.toStringAsFixed(6) ?? 'Not available',
                icon: Icons.gps_fixed_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      readOnly: true,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        filled: true,
        fillColor: AppColors.greenTint,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.mutedText),
        ),
      ],
    );
  }
}

class _PhotoInput extends StatelessWidget {
  const _PhotoInput({
    required this.photos,
    required this.maxPhotos,
    required this.onTakePhoto,
    required this.onRemove,
  });

  final List<Uint8List> photos;
  final int maxPhotos;
  final VoidCallback onTakePhoto;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    child: InkWell(
                      onTap: () => showPhotoViewer(context, bytes: photos[i]),
                      child: Image.memory(
                        photos[i],
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton.filled(
                      onPressed: () => onRemove(i),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.rejectedText,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(28, 28),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            if (photos.length < maxPhotos)
              OutlinedButton(
                onPressed: onTakePhoto,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(100, 100),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded),
                    SizedBox(height: 4),
                    Text('Add', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
        if (photos.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'At least 1 photo required',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.mutedText,
            ),
          ),
        ],
      ],
    );
  }
}
