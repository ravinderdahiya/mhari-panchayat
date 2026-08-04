import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/survey.dart';
import '../services/auth_service.dart';
import '../services/location_api.dart';
import '../services/survey_api.dart';
import '../theme/app_theme.dart';
import '../utils/photo_stamp.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/in_app_camera.dart';

class AssetSurveyFormScreen extends StatefulWidget {
  const AssetSurveyFormScreen({
    super.key,
    required this.departmentId,
    required this.assetTypeId,
    required this.assetTypeName,
    this.existingSurvey,
  });

  final int departmentId;
  final String assetTypeId;
  final String assetTypeName;
  final Survey? existingSurvey;

  @override
  State<AssetSurveyFormScreen> createState() => _AssetSurveyFormScreenState();
}

class _AssetSurveyFormScreenState extends State<AssetSurveyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _assetNameController = TextEditingController();
  final _districtController = TextEditingController();
  final _gpController = TextEditingController();
  final _villageController = TextEditingController();
  final _descriptionController = TextEditingController();

  late final DateTime _surveyDate;

  double? _lat;
  double? _lng;
  double? _accuracy;
  bool _gpsEnabled = false;
  bool _detectingLocation = false;
  SurveyCondition _condition = SurveyCondition.good;
  List<SurveyConditionOption> _conditionOptions = const [];
  bool _loadingConditionOptions = true;
  final List<Uint8List> _photos = [];
  bool _saving = false;
  String? _officerName;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSurvey;
    if (existing != null) {
      _surveyDate = existing.surveyDate;
      _assetNameController.text = existing.assetName;
      _districtController.text = existing.district;
      _gpController.text = existing.panchayat;
      _villageController.text = existing.village;
      _descriptionController.text = existing.description ?? '';
      _lat = existing.latitude;
      _lng = existing.longitude;
      _gpsEnabled = existing.latitude != null && existing.longitude != null;
      _condition = existing.condition;
    } else {
      _surveyDate = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) => _enableGps());
    }
    _loadOfficerName();
    _loadConditionOptions();
  }

  Future<void> _loadConditionOptions() async {
    try {
      final options = await SurveyApi.getSurveyConditions();
      if (!mounted) return;
      setState(() {
        _conditionOptions = options;
        _loadingConditionOptions = false;
        if (options.isNotEmpty &&
            !options.any((option) => option.value == _condition)) {
          _condition = options.first.value;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingConditionOptions = false);
    }
  }

  Future<void> _loadOfficerName() async {
    final session = await AuthService.getSession();
    if (!mounted) return;
    setState(() => _officerName = session?.officerName);
  }

  @override
  void dispose() {
    _assetNameController.dispose();
    _districtController.dispose();
    _gpController.dispose();
    _villageController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _dateLabel {
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
    final d = _surveyDate;
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _enableGps() async {
    if (_detectingLocation) return;
    setState(() => _detectingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('कृपया अपने डिवाइस की लोकेशन सर्विस चालू करें');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('स्थान दर्ज करने के लिए लोकेशन अनुमति आवश्यक है');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      String? detectedVillage;
      String? detectedPanchayat;
      String? detectedDistrict;
      try {
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          detectedVillage = (place.subLocality?.trim().isNotEmpty ?? false)
              ? place.subLocality!.trim()
              : place.locality?.trim();
          detectedPanchayat = (place.locality?.trim().isNotEmpty ?? false)
              ? place.locality!.trim()
              : detectedVillage;
          detectedDistrict =
              (place.subAdministrativeArea?.trim().isNotEmpty ?? false)
              ? place.subAdministrativeArea!.trim()
              : place.administrativeArea?.trim();
        }
      } catch (_) {
        // Native reverse geocoding is unavailable on Flutter web.
      }

      if (detectedVillage == null ||
          detectedPanchayat == null ||
          detectedDistrict == null) {
        try {
          final location = await LocationApi.reverse(
            latitude: position.latitude,
            longitude: position.longitude,
          );
          detectedVillage ??= location?.village;
          detectedPanchayat ??= location?.panchayat;
          detectedDistrict ??= location?.district;
        } catch (_) {
          // Coordinates remain usable when the online lookup is unavailable.
        }
      }

      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _accuracy = position.accuracy;
        _gpsEnabled = true;

        if (_villageController.text.trim().isEmpty && detectedVillage != null) {
          _villageController.text = detectedVillage;
        }
        if (_gpController.text.trim().isEmpty && detectedPanchayat != null) {
          _gpController.text = detectedPanchayat;
        }
        if (_districtController.text.trim().isEmpty &&
            detectedDistrict != null) {
          _districtController.text = detectedDistrict;
        }
      });
    } catch (_) {
      _showMessage('लोकेशन प्राप्त नहीं हो सकी। कृपया पुनः प्रयास करें।');
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) {
      _showMessage('अधिकतम 5 फोटो जोड़े जा सकते हैं');
      return;
    }
    try {
      final capturedBytes = await InAppCamera.capture(context);
      if (capturedBytes == null) return;
      var bytes = capturedBytes;

      if (!_gpsEnabled || _lat == null || _lng == null) {
        await _enableGps();
      }

      if (_lat != null && _lng != null) {
        try {
          bytes = await PhotoStamp.stamp(
            bytes: bytes,
            latitude: _lat!,
            longitude: _lng!,
          );
        } catch (_) {
          // Keep the unstamped photo if overlay rendering fails.
        }
      }

      if (!mounted) return;
      setState(() => _photos.add(bytes));
    } catch (_) {
      _showMessage('फोटो लेने में समस्या हुई। कृपया कैमरा अनुमति जांचें।');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    if (!_gpsEnabled || _lat == null || _lng == null) {
      _showMessage('Enable GPS to capture coordinates');
      return;
    }

    if (_photos.isEmpty) {
      _showMessage('कम से कम एक फोटो जोड़ें');
      return;
    }

    if (_conditionOptions.isEmpty) {
      _showMessage('Survey conditions could not be loaded from server.');
      return;
    }

    setState(() => _saving = true);
    try {
      final survey = await SurveyApi.submitSurvey(
        surveyId: widget.existingSurvey?.id,
        departmentId: widget.departmentId,
        assetTypeId: widget.assetTypeId,
        assetName: _assetNameController.text.trim(),
        district: _districtController.text.trim(),
        panchayat: _gpController.text.trim(),
        village: _villageController.text.trim(),
        latitude: _lat,
        longitude: _lng,
        description: _descriptionController.text.trim(),
        condition: _condition,
        surveyDate: _surveyDate,
        photos: _photos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Survey submitted · Asset ID: ${survey.assetId}',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      Navigator.of(context).pop();
    } on SurveyApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.greyBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Survey Form',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _HeaderCard(
                      assetName: widget.assetTypeName,
                      dateLabel: _dateLabel,
                      isUpdate: widget.existingSurvey != null,
                    ),
                    const SizedBox(height: 14),
                    _LabeledTextField(
                      label: 'Asset Name *',
                      controller: _assetNameController,
                      hint: 'Enter asset name',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _LabeledTextField(
                      label: 'District *',
                      controller: _districtController,
                      hint: 'Auto-filled from GPS',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _LabeledTextField(
                      label: 'Panchayat *',
                      controller: _gpController,
                      hint: 'Auto-filled from GPS',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _LabeledTextField(
                      label: 'Village *',
                      controller: _villageController,
                      hint: 'Auto-filled from GPS',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _GpsCoordinateField(
                      label: 'GPS Latitude *',
                      value: _lat,
                      available: _gpsEnabled,
                    ),
                    const SizedBox(height: 12),
                    _GpsCoordinateField(
                      label: 'GPS Longitude *',
                      value: _lng,
                      available: _gpsEnabled,
                    ),
                    const SizedBox(height: 12),
                    _GpsAccuracyRow(
                      enabled: _gpsEnabled,
                      busy: _detectingLocation,
                      accuracy: _accuracy,
                      onEnable: _enableGps,
                    ),
                    const SizedBox(height: 12),
                    _LabeledDropdown<String>(
                      label: 'Condition *',
                      value:
                          _conditionOptions.any(
                            (option) => option.value == _condition,
                          )
                          ? _conditionOptions
                                .firstWhere(
                                  (option) => option.value == _condition,
                                )
                                .label
                          : null,
                      items: _conditionOptions
                          .map((option) => option.label)
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _condition = _conditionOptions
                              .firstWhere((option) => option.label == v)
                              .value;
                        });
                      },
                    ),
                    if (!_loadingConditionOptions && _conditionOptions.isEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => _loadingConditionOptions = true);
                          _loadConditionOptions();
                        },
                        child: const Text('Retry loading conditions'),
                      ),
                    const SizedBox(height: 12),
                    _DescriptionField(controller: _descriptionController),
                    const SizedBox(height: 14),
                    _PhotosSection(
                      photos: _photos,
                      onAdd: _addPhoto,
                      onRemove: (i) => setState(() => _photos.removeAt(i)),
                    ),
                    const SizedBox(height: 14),
                    _SurveyedByRow(officerName: _officerName),
                  ],
                ),
              ),
            ),
            _BottomActions(
              busy: _saving,
              onCancel: () => Navigator.of(context).maybePop(),
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.assetName,
    required this.dateLabel,
    this.isUpdate = false,
  });

  final String assetName;
  final String dateLabel;
  final bool isUpdate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.assignment_turned_in_rounded,
                color: AppColors.secondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assetName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isUpdate ? 'Update Asset Survey' : 'New Asset Survey'} · $dateLabel',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: AppColors.mutedText,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: AppColors.mutedText,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _GpsCoordinateField extends StatelessWidget {
  const _GpsCoordinateField({
    required this.label,
    required this.value,
    required this.available,
  });

  final String label;
  final double? value;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: available ? AppColors.background : AppColors.greyBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: available
              ? Text(
                  value!.toStringAsFixed(6),
                  style: GoogleFonts.poppins(fontSize: 13),
                )
              : Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.pendingText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '⚠ Unable to fetch',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.pendingText,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _GpsAccuracyRow extends StatelessWidget {
  const _GpsAccuracyRow({
    required this.enabled,
    required this.busy,
    required this.accuracy,
    required this.onEnable,
  });

  final bool enabled;
  final bool busy;
  final double? accuracy;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GPS Accuracy',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (!enabled)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onEnable,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                busy ? 'Detecting...' : 'Enable GPS',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '± ${accuracy?.toStringAsFixed(1) ?? '--'} m',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          enabled ? '📍 Live GPS · Accurate' : '📍 Live GPS · Waiting for fix',
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }
}

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Description',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Describe the asset condition...',
            hintStyle: GoogleFonts.poppins(
              color: AppColors.mutedText,
              fontSize: 13,
            ),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Uint8List> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos (${photos.length}/5) *',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (photos.length < 5)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: const _DashedBorderPainter(color: AppColors.secondary),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.photo_camera_rounded,
                        color: AppColors.secondary,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to take a photo',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => showPhotoViewer(context, bytes: photos[i]),
                        child: Image.memory(
                          photos[i],
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: InkWell(
                        onTap: () => onRemove(i),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: AppColors.rejectedText,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(3),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SurveyedByRow extends StatelessWidget {
  const _SurveyedByRow({required this.officerName});

  final String? officerName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_rounded, size: 18, color: AppColors.mutedText),
          const SizedBox(width: 8),
          Text(
            'Surveyed by: ${officerName ?? '—'}',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.busy,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryText,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: busy ? null : onSubmit,
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: AppGradients.cta,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              '☁ Submit',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(12),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
