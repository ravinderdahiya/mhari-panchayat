import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Dashboard-style MapImageLayer: one `/export` for the viewport.
///
/// XYZ tile exports were slow because a phone requested many village-polygon
/// renders at once. One image matches the admin map and loads much faster.
class GisMapImageLayer extends StatefulWidget {
  const GisMapImageLayer({
    super.key,
    required this.controller,
    required this.mapServerUrl,
  });

  final MapController controller;
  final String mapServerUrl;

  @override
  State<GisMapImageLayer> createState() => _GisMapImageLayerState();
}

class _GisMapImageLayerState extends State<GisMapImageLayer> {
  static const _originShift = 20037508.342789244;
  static const _villageZoom = 9.0;
  static const _maxExportSide = 1024;

  OverlayImage? _overlay;
  StreamSubscription<MapEvent>? _events;
  Timer? _debounce;
  String? _lastUrl;
  int _loadGen = 0;
  LatLng? _lastCenter;
  double? _lastZoom;

  @override
  void initState() {
    super.initState();
    _events = widget.controller.mapEventStream.listen(_onMapEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _events?.cancel();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd ||
        event is MapEventFlingAnimationEnd ||
        event is MapEventDoubleTapZoomEnd) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 180), _refresh);
    }
  }

  void _refresh() {
    if (!mounted) return;
    MapCamera camera;
    try {
      camera = widget.controller.camera;
    } catch (_) {
      return;
    }

    final zoom = camera.zoom;
    final center = camera.center;
    if (_lastCenter != null &&
        _lastZoom != null &&
        (zoom - _lastZoom!).abs() < 0.15 &&
        const Distance().as(LengthUnit.Kilometer, _lastCenter!, center) <
            _moveThresholdKm(zoom)) {
      return;
    }

    final visible = camera.visibleBounds;
    final layers = zoom >= _villageZoom ? 'show:0,1' : 'show:0';

    var width = camera.nonRotatedSize.width.round();
    var height = camera.nonRotatedSize.height.round();
    final longest = math.max(width, height);
    if (longest > _maxExportSide) {
      final scale = _maxExportSide / longest;
      width = math.max(64, (width * scale).round());
      height = math.max(64, (height * scale).round());
    }

    final xmin = _lngToMercator(visible.west);
    final xmax = _lngToMercator(visible.east);
    final ymin = _latToMercator(visible.south);
    final ymax = _latToMercator(visible.north);

    final url = '${widget.mapServerUrl}/export'
        '?bbox=$xmin,$ymin,$xmax,$ymax'
        '&bboxSR=3857&imageSR=3857'
        '&size=$width,$height'
        '&layers=$layers'
        '&format=png32&transparent=true&f=image';

    if (url == _lastUrl) return;
    _lastUrl = url;
    _lastCenter = center;
    _lastZoom = zoom;

    final provider = NetworkImage(url);
    final gen = ++_loadGen;
    final overlayBounds = LatLngBounds(
      LatLng(visible.south, visible.west),
      LatLng(visible.north, visible.east),
    );

    precacheImage(provider, context).then((_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _overlay = OverlayImage(
          bounds: overlayBounds,
          imageProvider: provider,
        );
      });
    }).catchError((_) {});
  }

  static double _moveThresholdKm(double zoom) {
    if (zoom >= 12) return 0.4;
    if (zoom >= 10) return 1.2;
    if (zoom >= 9) return 3;
    return 12;
  }

  static double _lngToMercator(double lng) => lng * _originShift / 180;

  static double _latToMercator(double lat) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final y =
        math.log(math.tan((90 + clamped) * math.pi / 360)) / (math.pi / 180);
    return y * _originShift / 180;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: OverlayImageLayer(
        overlayImages: [?_overlay],
      ),
    );
  }
}
