import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../map/gis_map_image_layer.dart';
import '../models/asset.dart';
import '../models/complaint.dart';
import '../models/survey.dart';
import '../navigation/app_navigation.dart';
import '../services/asset_api.dart';
import '../services/complaint_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../widgets/complaint_widgets.dart';
import 'asset_details_screen.dart';
import 'complaint_details_screen.dart';

class ComplaintMapScreen extends StatefulWidget {
  const ComplaintMapScreen({super.key, this.staffQueue = false});

  /// When true, load the signed-in staff queue instead of the citizen's
  /// own complaints (CPLO / officer Map tab).
  final bool staffQueue;

  @override
  State<ComplaintMapScreen> createState() => _ComplaintMapScreenState();
}

class _ComplaintMapScreenState extends State<ComplaintMapScreen> {
  final _mapController = MapController();

  /// Same center as the admin dashboard map, but zoomed out a step further
  /// - the dashboard is a wide desktop map, while a phone's narrower
  /// portrait viewport needs a lower zoom for the full Haryana boundary to
  /// fit on screen instead of running off the left/right edges.
  /// Same center as the admin dashboard map, zoomed out one step for a
  /// phone's narrower portrait viewport. Can't go lower than this: the GIS
  /// district-boundary service (see GisMapImageLayer) has a minScale cutoff
  /// and stops rendering the boundary layer entirely below roughly zoom 7.6
  /// - confirmed 7.5 already loses it, 7.7 keeps it. That's the tightest
  /// zoom-out the boundary layer tolerates, so the full state doesn't quite
  /// fit edge-to-edge on a narrow screen without losing the boundaries.
  static const _haryanaCenter = LatLng(29.0588, 76.0856);
  static const _haryanaZoom = 7.7;

  static const _myLocationZoom = 15.0;
  static const _imageryTiles =
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _streetsTiles =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';

  LatLng? _myLocation;
  bool _streetsBasemap = false;

  List<Complaint> _complaints = [];
  List<AssetSummary> _assets = [];
  bool _loading = true;
  ComplaintBucket? _statusFilter;

  List<Complaint> get _geoComplaints => _complaints
      .where((c) => c.latitude != null && c.longitude != null)
      .where(
        (c) =>
            _statusFilter == null || complaintBucket(c.status) == _statusFilter,
      )
      .toList();

  List<AssetSummary> get _geoAssets =>
      _assets.where((a) => a.latitude != null && a.longitude != null).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyLocation());
    _loadComplaints();
    _loadAssets();
  }

  Future<void> _loadComplaints() async {
    setState(() => _loading = true);
    try {
      final complaints = widget.staffQueue
          ? await ComplaintApi.getOfficerQueue()
          : await ComplaintApi.getMine();
      if (!mounted) return;
      setState(() => _complaints = complaints);
    } on ComplaintApiException catch (_) {
      // Keep showing an empty map if complaints can't be loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAssets() async {
    try {
      final assets = await AssetApi.getAssets();
      if (!mounted) return;
      setState(() => _assets = assets);
    } catch (_) {
      // Keep showing the map without asset markers if this call fails.
    }
  }

  void _toggleFilter(ComplaintBucket bucket) {
    setState(() {
      _statusFilter = _statusFilter == bucket ? null : bucket;
    });
  }

  void _fitHaryana() {
    _mapController.move(_haryanaCenter, _haryanaZoom);
  }

  Future<void> _loadMyLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(position.latitude, position.longitude));
    } catch (_) {
      // Keep showing Haryana if location can't be read.
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _recenter() {
    final here = _myLocation;
    if (here != null) {
      _mapController.move(here, _myLocationZoom);
    } else {
      _fitHaryana();
      _loadMyLocation();
    }
  }

  Color _markerColor(ComplaintStatus status) {
    return switch (complaintBucket(status)) {
      ComplaintBucket.pending => const Color(0xFFD32F2F),
      ComplaintBucket.inProgress => const Color(0xFFF9A825),
      ComplaintBucket.resolved => const Color(0xFF2E7D32),
      ComplaintBucket.rejected => const Color(0xFF616161),
    };
  }

  Color _conditionColor(SurveyCondition condition) {
    return switch (condition) {
      SurveyCondition.good => const Color(0xFF2E7D32),
      SurveyCondition.fair => const Color(0xFFF9A825),
      SurveyCondition.poor => const Color(0xFFEF6C00),
      SurveyCondition.damaged => const Color(0xFFD32F2F),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildMapBody(context));
  }

  Widget _buildMapBody(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _haryanaCenter,
            initialZoom: _haryanaZoom,
            minZoom: 5,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: _streetsBasemap ? _streetsTiles : _imageryTiles,
              userAgentPackageName: 'com.example.my_first_app',
              errorTileCallback: (tile, error, stackTrace) {
                debugPrint('Tile load failed for ${tile.coordinates}: $error');
              },
            ),
            GisMapImageLayer(
              controller: _mapController,
              mapServerUrl: ApiConfig.gisPanchayatMapServerUrl,
            ),
            MarkerLayer(
              markers: [
                for (final asset in _geoAssets)
                  Marker(
                    point: LatLng(asset.latitude!, asset.longitude!),
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: _AssetMarker(
                      color: _conditionColor(asset.condition),
                      icon: assetTypeIcon(asset.iconKey ?? 'apartment'),
                      onTap: () =>
                          push(context, AssetDetailsScreen(assetId: asset.id)),
                    ),
                  ),
                for (final complaint in _geoComplaints)
                  Marker(
                    point: LatLng(complaint.latitude!, complaint.longitude!),
                    width: 44,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: _TeardropMarker(
                      color: _markerColor(complaint.status),
                      onTap: () => push(
                        context,
                        ComplaintDetailsScreen(complaint: complaint),
                      ),
                    ),
                  ),
                if (_myLocation != null)
                  Marker(
                    point: _myLocation!,
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    child: const _MyLocationDot(),
                  ),
              ],
            ),
          ],
        ),
        _buildSearchBar(context),
        _buildBasemapToggle(),
        Positioned(
          left: AppSpacing.screen,
          bottom: AppSpacing.screen,
          child: _MapLegend(selected: _statusFilter, onSelect: _toggleFilter),
        ),
        if (_loading)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 68,
            left: 0,
            right: 0,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ),
        Positioned(
          right: AppSpacing.screen,
          bottom: AppSpacing.screen,
          child: FloatingActionButton(
            heroTag: 'my_location',
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.primary,
            onPressed: _recenter,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildBasemapToggle() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 66,
      right: AppSpacing.screen,
      child: Material(
        color: AppColors.background,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BasemapChip(
                label: 'Map',
                selected: _streetsBasemap,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDDD3B2), Color(0xFFC9BE96)],
                ),
                onTap: () => setState(() => _streetsBasemap = true),
              ),
              const SizedBox(width: 6),
              _BasemapChip(
                label: 'Satellite',
                selected: !_streetsBasemap,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5A6E4C), Color(0xFF3F5233)],
                ),
                onTap: () => setState(() => _streetsBasemap = false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: AppSpacing.screen,
      right: AppSpacing.screen,
      child: Material(
        color: AppColors.background,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.search_rounded,
                size: 22,
                color: AppColors.mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    color: const Color(0xFF22281F),
                    height: 1.2,
                  ),
                  cursorColor: AppColors.primary,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Search location or complaint',
                    hintStyle: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      color: AppColors.navInactive,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasemapChip extends StatelessWidget {
  const _BasemapChip({
    required this.label,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 44,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brandBlue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _TeardropMarker extends StatelessWidget {
  const _TeardropMarker({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        Icons.location_on,
        color: color,
        size: 44,
        shadows: const [
          Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _AssetMarker extends StatelessWidget {
  const _AssetMarker({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.selected, required this.onSelect});

  final ComplaintBucket? selected;
  final ValueChanged<ComplaintBucket> onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STATUS',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.mutedText,
                ),
              ),
              const SizedBox(height: 6),
              _legendRow(
                const Color(0xFFD32F2F),
                'Pending',
                ComplaintBucket.pending,
              ),
              _legendRow(
                const Color(0xFFF9A825),
                'In Progress',
                ComplaintBucket.inProgress,
              ),
              _legendRow(
                const Color(0xFF2E7D32),
                'Resolved',
                ComplaintBucket.resolved,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String label, ComplaintBucket bucket) {
    final isSelected = selected == bucket;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(bucket),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : const Color(0xFF424242),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
