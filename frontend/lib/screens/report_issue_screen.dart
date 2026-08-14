import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/complaint_form_option.dart';
import '../models/complaint_category_option.dart';
import '../models/asset_type.dart';
import '../models/survey_department.dart';
import '../services/asset_type_api.dart';
import '../services/auth_service.dart';
import '../services/complaint_api.dart';
import '../services/fake_location_detector.dart';
import '../services/location_api.dart';
import '../theme/app_theme.dart';
import '../utils/photo_stamp.dart';
import '../widgets/common_widgets.dart';
import '../widgets/in_app_camera.dart';
import '../widgets/photo_viewer.dart';
import 'complaint_success_screen.dart';
import 'login_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  bool _busy = false;
  bool _loadingMasters = true;
  String? _error;
  Position? _lastPosition;
  ComplaintNamedOption? _district;
  ComplaintNamedOption? _tehsil;
  ComplaintVillageOption? _village;
  String? _gpsState;
  String? _gpsDistrict;
  String? _gpsTehsil;
  String? _gpsVillage;
  String? _gpsBlock;
  List<ComplaintCategoryOption> _categories = const [];
  List<ComplaintPriorityOption> _priorities = const [];
  List<SurveyDepartment> _departments = const [];
  List<AssetType> _assetTypes = const [];
  int? _departmentId;
  int? _assetTypeId;
  int? _categoryId;
  int? _priorityId;
  bool _loadingDepartments = true;
  bool _loadingAssets = false;
  bool _loadingCategories = false;
  bool _submitting = false;
  final List<Uint8List> _photos = [];
  static const _maxPhotos = 5;
  final _descriptionController = TextEditingController();

  Future<void> _loadDistricts() async {
    try {
      final options = await ComplaintApi.getFormOptions();
      if (mounted) {
        setState(() {
          _categories = options.categories;
          _priorities = options.priorities;
          if (_priorityId == null && options.priorities.isNotEmpty) {
            final medium = options.priorities.indexWhere(
              (item) => item.name.toLowerCase() == 'medium',
            );
            _priorityId = medium >= 0
                ? options.priorities[medium].id
                : options.priorities.first.id;
          }
        });
      }
    } on ComplaintApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingMasters = false);
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final departments = await AssetTypeApi.getDepartments();
      if (mounted) setState(() => _departments = departments);
    } on AssetTypeApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingDepartments = false);
    }
  }

  Future<void> _selectDepartment(int? departmentId) async {
    setState(() {
      _departmentId = departmentId;
      _assetTypeId = null;
      _assetTypes = const [];
      _categoryId = null;
      _categories = const [];
    });
    if (departmentId == null) return;
    setState(() => _loadingAssets = true);
    try {
      final assets = await AssetTypeApi.getAssetTypes(
        departmentId: departmentId,
      );
      if (mounted && _departmentId == departmentId) {
        setState(() => _assetTypes = assets);
      }
    } on AssetTypeApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  Future<void> _selectAssetType(int? assetTypeId) async {
    setState(() {
      _assetTypeId = assetTypeId;
      _categoryId = null;
      _categories = const [];
    });
    if (assetTypeId == null) return;
    setState(() => _loadingCategories = true);
    try {
      final categories = await ComplaintApi.getCategories(
        assetTypeId: assetTypeId,
        departmentId: _departmentId,
      );
      if (!mounted || _assetTypeId != assetTypeId) return;
      setState(() => _categories = categories);
    } on ComplaintApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      if (_lastPosition != null) {
        try {
          bytes = await PhotoStamp.stamp(
            bytes: bytes,
            latitude: _lastPosition!.latitude,
            longitude: _lastPosition!.longitude,
          );
        } catch (_) {}
      }
      if (mounted) setState(() => _photos.add(bytes));
    } catch (_) {
      _showMessage('Photo could not be captured. Check camera permission.');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_lastPosition == null ||
        (_gpsDistrict?.trim().isEmpty ?? true) ||
        (_gpsVillage?.trim().isEmpty ?? true)) {
      _showMessage('Please capture GPS location first');
      return;
    }
    if (_departmentId == null || _assetTypeId == null) {
      _showMessage('Please select department and asset');
      return;
    }
    if (_priorityId == null) {
      _showMessage('Please select priority');
      return;
    }
    if (_categories.isNotEmpty && _categoryId == null) {
      _showMessage('Please select category');
      return;
    }
    final description = _descriptionController.text.trim();
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
        districtId: _district?.id,
        tehsilId: _tehsil?.id,
        villageId: _village?.id,
        locationState: _gpsState,
        locationDistrict: _gpsDistrict,
        locationTehsil: _gpsTehsil,
        locationVillage: _gpsVillage,
        locationBlock: _gpsBlock,
        categoryId: _categoryId,
        priorityId: _priorityId!,
        description: description,
        latitude: _lastPosition?.latitude,
        longitude: _lastPosition?.longitude,
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

  Future<DetectedLocation?> _resolveFromDynamicMasters(Placemark place) async {
    final rootOptions = await ComplaintApi.getFormOptions();
    final districtCandidates = <String?>[
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
    ];
    final districtChoices = _orderedNameMatches(
      rootOptions.districts,
      districtCandidates,
    );

    for (final district in districtChoices) {
      final districtOptions = await ComplaintApi.getFormOptions(
        districtId: district.id,
      );
      final tehsil = _firstNameMatch(districtOptions.tehsils, [
        place.locality,
        place.subLocality,
        district.name,
      ]);
      if (tehsil == null) continue;

      final tehsilOptions = await ComplaintApi.getFormOptions(
        districtId: district.id,
        tehsilId: tehsil.id,
      );
      final village = _firstNameMatch(tehsilOptions.villages, [
        place.subLocality,
        place.locality,
        place.name,
        tehsil.name,
      ]);
      if (village == null) continue;

      return DetectedLocation(
        districtId: district.id,
        district: district.name,
        tehsilId: tehsil.id,
        tehsil: tehsil.name,
        villageId: village.id,
        village: village.name,
        panchayatId: village.panchayatId,
        panchayat: village.panchayatName,
      );
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadDistricts();
    _loadDepartments();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _detectAndOpen() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationFailure(
          'Please turn on phone location services and try again.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'Location permission is permanently denied. Enable it from app settings.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationFailure(
          'Location permission is required to file a complaint.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (await FakeLocationDetector.isFakeLocation()) {
        throw const _LocationFailure(
          'Fake/mock location detected. Turn off any location-spoofing app and use your real GPS location to file a complaint.',
        );
      }

      _lastPosition = position;
      if (!mounted) return;

      DetectedLocation? detected;
      Placemark? nativePlace;
      try {
        final places = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (places.isNotEmpty) {
          final place = places.first;
          nativePlace = place;
          if (mounted) {
            setState(() {
              _gpsState = place.administrativeArea ?? 'Haryana';
              _gpsDistrict =
                  place.subAdministrativeArea ?? place.administrativeArea;
              _gpsTehsil = place.locality ?? place.subAdministrativeArea;
              _gpsVillage = place.subLocality ?? place.name ?? place.locality;
              _gpsBlock = place.locality ?? place.subAdministrativeArea;
              _error = null;
            });
          }
          detected = await LocationApi.resolve(
            district: place.subAdministrativeArea ?? place.administrativeArea,
            tehsil: place.locality,
            village: place.subLocality ?? place.locality,
            panchayat: place.name,
            administrativeArea: place.administrativeArea,
            subAdministrativeArea: place.subAdministrativeArea,
            locality: place.locality,
            subLocality: place.subLocality,
            name: place.name,
          );

          // Android geocoders often report an urban colony as subLocality
          // and the city/tehsil as locality. Try the locality itself as the
          // master village when the most detailed result is incomplete.
          if (!_hasCompleteHierarchy(detected)) {
            final localityMatch = await LocationApi.resolve(
              district: place.subAdministrativeArea ?? place.administrativeArea,
              tehsil: place.locality,
              village: place.locality,
              panchayat: place.locality ?? place.name,
              administrativeArea: place.administrativeArea,
              subAdministrativeArea: place.subAdministrativeArea,
              locality: place.locality,
              subLocality: place.subLocality,
              name: place.name,
            );
            detected = _preferMoreComplete(detected, localityMatch);
          }

          // Some phone map data still returns a former parent district. For
          // example, locations in the new Hansi district can be labelled
          // Hisar. Matching locality as district + tehsil resolves that
          // master hierarchy without exposing editable fields to the user.
          if (!_hasCompleteHierarchy(detected) &&
              (place.locality?.trim().isNotEmpty ?? false)) {
            final localityHierarchy = await LocationApi.resolve(
              district: place.locality,
              tehsil: place.locality,
              village: place.locality,
              panchayat: place.locality,
              administrativeArea: place.administrativeArea,
              subAdministrativeArea: place.subAdministrativeArea,
              locality: place.locality,
              subLocality: place.subLocality,
              name: place.name,
            );
            detected = _preferMoreComplete(detected, localityHierarchy);
          }
        }
      } catch (_) {
        // Server reverse geocoding remains as a secondary source.
      }
      if (!_hasCompleteHierarchy(detected)) {
        final reversed = await LocationApi.reverse(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        if (_resolvedHierarchyParts(reversed) >
            _resolvedHierarchyParts(detected)) {
          detected = reversed;
        }
      }

      if (!_hasCompleteHierarchy(detected) && nativePlace != null) {
        final masterMatch = await _resolveFromDynamicMasters(nativePlace);
        detected = _preferMoreComplete(detected, masterMatch);
      }

      final districtId = detected?.districtId;
      final tehsilId = detected?.tehsilId;
      final villageId = detected?.villageId;
      if (!mounted) return;
      setState(() {
        _gpsState ??= 'Haryana';
        _gpsDistrict ??= detected?.district;
        _gpsTehsil ??= detected?.tehsil;
        _gpsVillage ??= detected?.village;
        _gpsBlock ??= detected?.panchayat;
        _error = null;
      });

      // Master IDs are optional routing metadata. GPS address display and
      // complaint capture must not fail when a geocoder name differs from a
      // master name.
      if (districtId != null && tehsilId != null && villageId != null) {
        final options = await ComplaintApi.getFormOptions(
          districtId: districtId,
          tehsilId: tehsilId,
        );
        final district = _firstWhereOrNull(
          options.districts,
          (item) => item.id == districtId,
        );
        final tehsil = _firstWhereOrNull(
          options.tehsils,
          (item) => item.id == tehsilId,
        );
        final village = _firstWhereOrNull(
          options.villages,
          (item) => item.id == villageId,
        );
        if (mounted && district != null && tehsil != null && village != null) {
          setState(() {
            _categories = options.categories;
            _priorities = options.priorities;
            _district = district;
            _tehsil = tehsil;
            _village = village;
            if (village.blockName.trim().isNotEmpty) {
              _gpsBlock = village.blockName;
            }
          });
        }
      }
    } on _LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on ComplaintApiException catch (e) {
      if (e.isUnauthenticated) {
        await AuthService.logout();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Location could not be detected. Check GPS and internet, then retry.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'New Complaint',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location Details',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '(GPS is Mandatory)',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.mutedText,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _detectAndOpen,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_on_rounded, size: 20),
                    label: Text(
                      _busy
                          ? 'Capturing GPS Location…'
                          : 'Capture GPS Location',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blueTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.inProgressText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tip: Capture GPS from your current location for best accuracy.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.inProgressText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.rejectedBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.rejectedText,
                ),
              ),
            ),
          ],
          if (_lastPosition != null && _error == null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 7),
                  Text('GPS location captured successfully'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _fixedField('State', _gpsState ?? 'Select State'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _fixedField(
                  'District *',
                  _gpsDistrict ?? 'Select District',
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _fixedField('Tehsil', _gpsTehsil ?? 'Select Tehsil'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _fixedField(
                  'Village *',
                  _gpsVillage ?? 'Select Village',
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _fixedField('Block *', _gpsBlock ?? 'Select Block'),
          if (_loadingMasters) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Complaint Details',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _departmentId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Department *',
              prefixIcon: const Icon(Icons.account_balance_outlined),
              suffixIcon: _loadingDepartments
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
              for (final department in _departments)
                DropdownMenuItem(
                  value: department.id,
                  child: Text(department.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _loadingDepartments ? null : _selectDepartment,
          ),
          const SizedBox(height: 12),
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
                : _selectAssetType,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _assetTypeId != null && _categories.isEmpty && !_loadingCategories
                  ? 'Complaint Category (not required for this asset)'
                  : 'Complaint Category *',
              prefixIcon: const Icon(Icons.category_outlined),
              suffixIcon: _loadingCategories
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
              for (final category in _categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: _loadingCategories || _categories.isEmpty
                ? null
                : (value) {
                    final category = _firstWhereOrNull(
                      _categories,
                      (item) => item.id == value,
                    );
                    setState(() {
                      _categoryId = value;
                      if (category?.defaultPriorityId != null) {
                        _priorityId = category!.defaultPriorityId;
                      }
                    });
                  },
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
              for (final priority in _priorities)
                DropdownMenuItem(
                  value: priority.id,
                  child: Text(priority.name),
                ),
            ],
            onChanged: (value) => setState(() => _priorityId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Description *',
              hintText: 'Describe the issue and exact location…',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Issue Photos * (up to $_maxPhotos)',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => showPhotoViewer(
                          context,
                          bytes: _photos[i],
                        ),
                        child: Image.memory(
                          _photos[i],
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
                        onPressed: () => setState(() => _photos.removeAt(i)),
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
              if (_photos.length < _maxPhotos)
                OutlinedButton(
                  onPressed: _takePhoto,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(100, 100),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined),
                      SizedBox(height: 4),
                      Text('Add', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Submitting…' : 'Submit Complaint'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixedField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          height: 50,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.greyBg.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(value, style: GoogleFonts.poppins(fontSize: 15)),
        ),
      ],
    );
  }
}

class _LocationFailure implements Exception {
  const _LocationFailure(this.message);

  final String message;
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

String _normalizeMasterName(String? value) {
  return (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(
        RegExp(
          r'\b(district|division|tehsil|tahsil|sub tehsil|sub district)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

T? _firstNameMatch<T extends ComplaintNamedOption>(
  List<T> items,
  List<String?> candidates,
) {
  final names = candidates
      .map(_normalizeMasterName)
      .where((name) => name.length >= 2)
      .toSet();
  for (final candidate in names) {
    final exact = _firstWhereOrNull(
      items,
      (item) => _normalizeMasterName(item.name) == candidate,
    );
    if (exact != null) return exact;
  }
  for (final candidate in names.where((name) => name.length >= 4)) {
    final partial = _firstWhereOrNull(items, (item) {
      final name = _normalizeMasterName(item.name);
      return name.contains(candidate) || candidate.contains(name);
    });
    if (partial != null) return partial;
  }
  return null;
}

List<T> _orderedNameMatches<T extends ComplaintNamedOption>(
  List<T> items,
  List<String?> candidates,
) {
  final matches = <T>[];
  for (final candidate in candidates) {
    final match = _firstNameMatch(items, [candidate]);
    if (match != null && !matches.any((item) => item.id == match.id)) {
      matches.add(match);
    }
  }
  return matches;
}

bool _hasCompleteHierarchy(DetectedLocation? location) {
  return location?.districtId != null &&
      location?.tehsilId != null &&
      location?.villageId != null;
}

int _resolvedHierarchyParts(DetectedLocation? location) {
  if (location == null) return 0;
  return [
    location.districtId,
    location.tehsilId,
    location.villageId,
  ].where((id) => id != null).length;
}

DetectedLocation? _preferMoreComplete(
  DetectedLocation? current,
  DetectedLocation? candidate,
) {
  return _resolvedHierarchyParts(candidate) > _resolvedHierarchyParts(current)
      ? candidate
      : current;
}
