import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

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
  const ComplaintMapScreen({super.key});

  @override
  State<ComplaintMapScreen> createState() => _ComplaintMapScreenState();
}

class _ComplaintMapScreenState extends State<ComplaintMapScreen> {
  final _mapController = MapController();

  static const _initialCenter = LatLng(28.3521, 77.0642);
  static const _initialZoom = 12.0;
  static const _myLocationZoom = 15.0;

  LatLng? _myLocation;

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
      final complaints = await ComplaintApi.getMine();
      if (!mounted) return;
      setState(() => _complaints = complaints);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToComplaints());
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToComplaints());
  }

  void _fitToComplaints() {
    final points = _geoComplaints
        .map((c) => LatLng(c.latitude!, c.longitude!))
        .toList();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, _myLocationZoom);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(40, 100, 40, 220),
      ),
    );
  }

  Future<void> _loadMyLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final here = LatLng(position.latitude, position.longitude);
      setState(() => _myLocation = here);
      if (_geoComplaints.isEmpty) {
        _mapController.move(here, _myLocationZoom);
      }
    } catch (_) {
      // Keep showing the default map center if location can't be read.
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
      _mapController.move(_initialCenter, _initialZoom);
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
            initialCenter: _initialCenter,
            initialZoom: _initialZoom,
            minZoom: 4,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.example.my_first_app',
              errorTileCallback: (tile, error, stackTrace) {
                debugPrint('Tile load failed for ${tile.coordinates}: $error');
              },
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
        Positioned(
          left: AppSpacing.screen,
          bottom: AppSpacing.screen,
          child: _MapLegend(selected: _statusFilter, onSelect: _toggleFilter),
        ),
        if (_loading)
          const Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: Center(
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

  Widget _buildSearchBar(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: AppSpacing.screen,
      right: AppSpacing.screen,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(30),
        shadowColor: Colors.black26,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF616161)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search location or complaint',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: const Color(0xFF9E9E9E),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Legend',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 8),
          _legendRow(
            const Color(0xFFD32F2F),
            'Pending',
            ComplaintBucket.pending,
          ),
          const SizedBox(height: 6),
          _legendRow(
            const Color(0xFFF9A825),
            'In Progress',
            ComplaintBucket.inProgress,
          ),
          const SizedBox(height: 6),
          _legendRow(
            const Color(0xFF2E7D32),
            'Resolved',
            ComplaintBucket.resolved,
          ),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
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
