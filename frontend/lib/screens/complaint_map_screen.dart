import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../map/gis_map_image_layer.dart';
import '../map/marker_clusterer.dart';
import '../models/asset.dart';
import '../models/complaint.dart';
import '../models/survey.dart';
import '../navigation/app_navigation.dart';
import '../services/asset_api.dart';
import '../services/complaint_api.dart';
import '../services/location_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../utils/responsive.dart';
import '../widgets/complaint_widgets.dart';
import '../widgets/flipping_logo.dart';
import 'asset_details_screen.dart';
import 'complaint_details_screen.dart';

class ComplaintMapScreen extends StatefulWidget {
  const ComplaintMapScreen({
    super.key,
    this.staffQueue = false,
    this.showComplaints = true,
  });

  /// When true, load the signed-in staff queue instead of the citizen's
  /// own complaints (CPLO / officer Map tab).
  final bool staffQueue;

  /// CPLO's Map tab is asset-survey only - they don't handle complaints at
  /// all, so this skips the complaints fetch/markers/legend/status-filter
  /// entirely and shows just the asset-survey layer.
  final bool showComplaints;

  @override
  State<ComplaintMapScreen> createState() => _ComplaintMapScreenState();
}

class _ComplaintMapScreenState extends State<ComplaintMapScreen> {
  final _mapController = MapController();

  // Marker clustering: the camera is read at build time, so the map just asks
  // for a (throttled) rebuild whenever it moves or zooms.
  StreamSubscription<MapEvent>? _mapSub;
  Timer? _clusterTimer;

  // --- place search (search bar + Panchayat/Block/District chips)
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  String? _searchLevel; // null = all levels
  List<PlaceHit> _hits = [];
  bool _searching = false;
  bool _searchedOnce = false;

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

  /// Deepest zoom the user can reach. The ArcGIS basemaps only have real tiles up
  /// to a certain level (beyond it they return a "Map data not yet available"
  /// placeholder image), so the TileLayer is capped at the native levels below
  /// and the last real tiles are scaled up instead. Measured over Haryana
  /// villages: imagery has real tiles to z18, the street map to z17.
  static const _maxZoom = 20.0;
  static const _imageryNativeZoom = 18;
  static const _streetsNativeZoom = 17;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The map controller only exists once FlutterMap has been built.
      _mapSub = _mapController.mapEventStream.listen(_onMapEvent);
      setState(() {}); // first real camera -> first clustering
    });
    if (widget.showComplaints) {
      _loadComplaints();
    } else {
      _loading = false;
    }
    // The complaints map shows complaints only; the asset layer belongs to the
    // asset-survey maps (CPLO / reviewers, showComplaints: false).
    if (!widget.showComplaints) _loadAssets();
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
      setState(
        () => _myLocation = LatLng(position.latitude, position.longitude),
      );
    } catch (_) {
      // Keep showing Haryana if location can't be read.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mapSub?.cancel();
    _clusterTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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

  // ------------------------------------------------------------- clustering

  void _onMapEvent(MapEvent event) {
    if (_clusterTimer?.isActive ?? false) return;
    _clusterTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  int _conditionSeverity(SurveyCondition condition) => switch (condition) {
    SurveyCondition.good => 0,
    SurveyCondition.fair => 1,
    SurveyCondition.poor => 2,
    SurveyCondition.damaged => 3,
  };

  int _complaintSeverity(ComplaintStatus status) => switch (complaintBucket(status)) {
    ComplaintBucket.pending => 3,
    ComplaintBucket.inProgress => 1,
    ComplaintBucket.resolved => 0,
    ComplaintBucket.rejected => 0,
  };

  List<MapPoint> _mapPoints() => [
    for (final asset in _geoAssets)
      MapPoint(
        id: 'asset_${asset.id}',
        position: LatLng(asset.latitude!, asset.longitude!),
        color: _conditionColor(asset.condition),
        severity: _conditionSeverity(asset.condition),
        title: asset.assetName,
        subtitle: '${asset.assetTypeName ?? 'Asset'} · ${asset.condition.name}',
        icon: assetTypeIcon(asset.iconKey ?? 'apartment'),
        isComplaint: false,
        onTap: () => push(context, AssetDetailsScreen(assetId: asset.id)),
      ),
    if (widget.showComplaints)
      for (final complaint in _geoComplaints)
        MapPoint(
          id: 'complaint_${complaint.id}',
          position: LatLng(complaint.latitude!, complaint.longitude!),
          color: _markerColor(complaint.status),
          severity: _complaintSeverity(complaint.status),
          title: complaint.displaySubject,
          subtitle: '${statusLabel(complaint.status)} · ${complaint.locationLabel}',
          icon: Icons.report_problem_rounded,
          isComplaint: true,
          onTap: () => push(context, ComplaintDetailsScreen(complaint: complaint)),
        ),
  ];

  /// Asset / complaint markers for the current camera: nearby ones merged into
  /// count bubbles, the rest drawn at a size that suits the zoom level.
  List<Marker> _clusterMarkers() {
    MapCamera camera;
    try {
      camera = _mapController.camera;
    } catch (_) {
      return const []; // FlutterMap not laid out yet - the post-frame rebuild fills this in
    }

    final size = markerSizeForZoom(camera.zoom);

    return [
      for (final cluster in clusterPoints(_mapPoints(), camera))
        cluster.isSingle ? _singleMarker(cluster.points.first, size) : _clusterMarker(cluster),
    ];
  }

  Marker _singleMarker(MapPoint point, double size) {
    if (point.isComplaint) {
      final pin = size * 1.1;

      return Marker(
        point: point.position,
        width: math.max(pin, 30),
        height: math.max(pin * 1.18, 34),
        alignment: Alignment.topCenter,
        child: _TeardropMarker(color: point.color, onTap: point.onTap, size: pin),
      );
    }

    final tapSize = math.max(size, 30.0); // keep small dots easy to tap

    return Marker(
      point: point.position,
      width: tapSize,
      height: tapSize,
      alignment: Alignment.center,
      child: _AssetMarker(color: point.color, icon: point.icon, onTap: point.onTap, size: size),
    );
  }

  Marker _clusterMarker(MapCluster cluster) {
    final diameter = clusterSizeFor(cluster.count);

    return Marker(
      point: cluster.center,
      width: diameter + 10,
      height: diameter + 10,
      alignment: Alignment.center,
      child: _ClusterBubble(
        count: cluster.count,
        color: cluster.worst.color,
        size: diameter,
        onTap: () => _openCluster(cluster),
      ),
    );
  }

  /// Tapping a bubble zooms in to its members; if they can never separate (same
  /// spot, or already at maximum zoom) it lists them instead.
  void _openCluster(MapCluster cluster) {
    final camera = _mapController.camera;
    if (cluster.isCoLocated || camera.zoom >= _maxZoom - 0.5) {
      _showClusterList(cluster);
      return;
    }

    final fitted = CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([for (final p in cluster.points) p.position]),
      padding: const EdgeInsets.all(72),
      maxZoom: _maxZoom,
    ).fit(camera);
    final zoom = math.max(fitted.zoom, camera.zoom + 1).clamp(5.0, _maxZoom);
    _mapController.move(fitted.center, zoom);
  }

  void _showClusterList(MapCluster cluster) {
    final points = [...cluster.points]..sort((a, b) => b.severity.compareTo(a.severity));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '${cluster.count} items here',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: points.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
                  itemBuilder: (context, index) {
                    final point = points[index];

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: point.color,
                        child: Icon(point.icon, color: Colors.white, size: 17),
                      ),
                      title: Text(point.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(point.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        point.onTap();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  Widget build(BuildContext context) => _buildCitizenHome(context);

  int _countFor(ComplaintBucket bucket) =>
      _complaints.where((c) => complaintBucket(c.status) == bucket).length;

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what will be available soon')));
  }

  // ------------------------------------------------------------------ search

  String get _searchHint => switch (_searchLevel) {
    'panchayat' => 'Search Panchayat...',
    'block' => 'Search Block...',
    'district' => 'Search District...',
    _ => 'Search Panchayat, Village, Block...',
  };

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      _searchSeq++;
      setState(() {
        _hits = [];
        _searching = false;
        _searchedOnce = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    final hits = await LocationApi.search(query, level: _searchLevel);
    if (!mounted || seq != _searchSeq)
      return; // a newer search superseded this one
    setState(() {
      _hits = hits;
      _searching = false;
      _searchedOnce = true;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchSeq++;
    _searchController.clear();
    setState(() {
      _hits = [];
      _searching = false;
      _searchedOnce = false;
    });
  }

  Future<void> _openHit(PlaceHit hit) async {
    _searchFocus.unfocus();
    _searchController.text = hit.name;
    setState(() {
      _hits = [];
      _searchedOnce = false;
      _searching = true;
    });

    final extent = await LocationApi.extent(level: hit.level, id: hit.id);
    if (!mounted) return;
    setState(() => _searching = false);

    if (extent == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Boundary for ${hit.name} is not available on the map',
            ),
          ),
        );
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(extent.ymin, extent.xmin),
          LatLng(extent.ymax, extent.xmax),
        ),
        padding: const EdgeInsets.fromLTRB(32, 210, 32, 48),
        maxZoom: 16,
      ),
    );
  }

  void _showLayers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Map layers',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _BasemapChip(
                    label: 'Map',
                    selected: _streetsBasemap,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDDD3B2), Color(0xFFC9BE96)],
                    ),
                    onTap: () {
                      setState(() => _streetsBasemap = true);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  const SizedBox(width: 10),
                  _BasemapChip(
                    label: 'Satellite',
                    selected: !_streetsBasemap,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5A6E4C), Color(0xFF3F5233)],
                    ),
                    onTap: () {
                      setState(() => _streetsBasemap = false);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Distance the map overlays keep from the bottom edge.
  double get _overlayBottom => 12;

  Widget _buildCitizenHome(BuildContext context) {
    // Tablets: the search bar spans the width with the layers button at its
    // right end; the recenter button sits bottom-right on every device.
    final tablet = context.isTablet;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const _CitizenHomeHeader(),
          Expanded(
            child: Stack(
              children: [
                _buildMap(),
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _HomeSearchBar(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          hint: _searchHint,
                          loading: _searching,
                          onChanged: _onSearchChanged,
                          onClear: _clearSearch,
                          onMic: () => _comingSoon('Voice search'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LayersButton(onTap: _showLayers),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: _overlayBottom,
                  child: _MapSquareButton(
                    icon: Icons.my_location_rounded,
                    onTap: _recenter,
                    size: tablet ? 54 : 42,
                  ),
                ),
                if (widget.showComplaints)
                  Positioned(
                    left: 12,
                    bottom: _overlayBottom,
                    child: _IssueStatusCard(
                      selected: _statusFilter,
                      onSelect: _toggleFilter,
                      pending: _countFor(ComplaintBucket.pending),
                      inProgress: _countFor(ComplaintBucket.inProgress),
                      resolved: _countFor(ComplaintBucket.resolved),
                    ),
                  ),
                if (_loading)
                  const Positioned(
                    top: 66,
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
                if (_hits.isNotEmpty || (_searchedOnce && !_searching))
                  Positioned(
                    top: 58,
                    left: 12,
                    // Line the results up under the search bar, not the buttons.
                    right: tablet ? 12 + 44 + 10 : 12,
                    child: _SearchResults(hits: _hits, onTap: _openHit),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: _haryanaCenter,
        initialZoom: _haryanaZoom,
        minZoom: 5,
        maxZoom: _maxZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: _streetsBasemap ? _streetsTiles : _imageryTiles,
          // Past this level keep scaling the last real tile instead of fetching
          // placeholder tiles.
          maxNativeZoom: _streetsBasemap ? _streetsNativeZoom : _imageryNativeZoom,
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
            ..._clusterMarkers(),
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
          style: GoogleFonts.poppins(
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
  const _TeardropMarker({required this.color, required this.onTap, this.size = 44});

  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        Icons.location_on,
        color: color,
        size: size,
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
    this.size = 40,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final showIcon = size >= 18; // tiny zoomed-out dots carry colour only

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: size < 18 ? 1.5 : 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: showIcon ? Icon(icon, color: Colors.white, size: size * 0.5) : null,
        ),
      ),
    );
  }
}

/// Count bubble for a group of nearby markers: a soft halo, a solid disc in the
/// colour of the group's worst item, and the number of items inside.
class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({
    required this.count,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final int count;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count > 999 ? '999+' : '$count';
    final dark = ThemeData.estimateBrightnessForColor(color) == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Center(
        child: Container(
          width: size + 10,
          height: size + 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.30)),
          alignment: Alignment.center,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2)),
              ],
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: label.length > 3 ? 10 : (label.length > 2 ? 11 : 12.5),
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : const Color(0xFF22281F),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _kGreen = Color(0xFF1B6B43);

const _kOrange = Color(0xFFF58220);

TextStyle _pop(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
}) => GoogleFonts.poppins(
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.ink,
);

class _CitizenHomeHeader extends StatelessWidget {
  const _CitizenHomeHeader();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        top + 8,
        AppSpacing.screen,
        10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const FlippingLogo(),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Mhari ',
                      style: _pop(20, weight: FontWeight.w700, color: _kGreen),
                    ),
                    TextSpan(
                      text: 'Panchayat',
                      style: _pop(20, weight: FontWeight.w700, color: _kOrange),
                    ),
                  ],
                ),
              ),
              Text(
                'मेरी पंचायत - सशक्त पंचायत, समृद्ध हरियाणा',
                style: _pop(8.5, weight: FontWeight.w600, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.loading,
    required this.onChanged,
    required this.onClear,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool loading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.ink, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: _pop(14, weight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: hint,
                  hintMaxLines: 1,
                  hintStyle: _pop(
                    13.5,
                    weight: FontWeight.w400,
                    color: AppColors.mutedText,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onMic,
                      icon: Icon(
                        Icons.mic_none_rounded,
                        color: AppColors.ink,
                        size: 22,
                      ),
                    )
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.ink,
                        size: 20,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.hits, required this.onTap});

  final List<PlaceHit> hits;
  final ValueChanged<PlaceHit> onTap;

  IconData _icon(String level) => switch (level) {
    'district' => Icons.location_on_rounded,
    'block' => Icons.apartment_rounded,
    'panchayat' => Icons.home_rounded,
    _ => Icons.holiday_village_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: hits.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No places found',
                  style: _pop(
                    12.5,
                    weight: FontWeight.w400,
                    color: AppColors.mutedText,
                  ),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: hits.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final hit = hits[index];

                  return ListTile(
                    dense: true,
                    leading: Icon(_icon(hit.level), color: _kGreen, size: 22),
                    title: Text(
                      hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _pop(13, weight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _pop(
                        11,
                        weight: FontWeight.w400,
                        color: AppColors.mutedText,
                      ),
                    ),
                    onTap: () => onTap(hit),
                  );
                },
              ),
      ),
    );
  }
}

class _LayersButton extends StatelessWidget {
  const _LayersButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Layers',
      child: Material(
        color: _kGreen,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.layers_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _MapSquareButton extends StatelessWidget {
  const _MapSquareButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size >= 54 ? 26 : 22, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _IssueStatusCard extends StatefulWidget {
  const _IssueStatusCard({
    required this.selected,
    required this.onSelect,
    required this.pending,
    required this.inProgress,
    required this.resolved,
  });

  final ComplaintBucket? selected;
  final ValueChanged<ComplaintBucket> onSelect;
  final int pending;
  final int inProgress;
  final int resolved;

  @override
  State<_IssueStatusCard> createState() => _IssueStatusCardState();
}

class _IssueStatusCardState extends State<_IssueStatusCard> {
  static const _pendingColor = Color(0xFFE53935);
  static const _inProgressColor = Color(0xFFF9A825);
  static const _resolvedColor = Color(0xFF2E9D4F);

  // Starts collapsed so the map stays clear; the collapsed pill still shows
  // the colour-coded counts so users know what is inside.
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.bottomLeft,
        child: _expanded ? _buildExpanded() : _buildCollapsed(),
      ),
    );
  }

  Widget _buildCollapsed() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Issues', style: _pop(12, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            _countDot(_pendingColor, widget.pending),
            const SizedBox(width: 8),
            _countDot(_inProgressColor, widget.inProgress),
            const SizedBox(width: 8),
            _countDot(_resolvedColor, widget.resolved),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _countDot(Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$count', style: _pop(12, weight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildExpanded() {
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _toggle,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Issue Status',
                      style: _pop(13, weight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _row(
              _pendingColor,
              'Pending',
              widget.pending,
              ComplaintBucket.pending,
            ),
            _row(
              _inProgressColor,
              'In Progress',
              widget.inProgress,
              ComplaintBucket.inProgress,
            ),
            _row(
              _resolvedColor,
              'Resolved',
              widget.resolved,
              ComplaintBucket.resolved,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Color color, String label, int count, ComplaintBucket bucket) {
    final isSelected = widget.selected == bucket;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onSelect(bucket),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: _pop(
                  12,
                  weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '($count)',
              style: _pop(
                12,
                weight: FontWeight.w500,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
