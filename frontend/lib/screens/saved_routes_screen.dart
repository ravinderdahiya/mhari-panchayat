import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/route_track.dart';
import '../services/route_api.dart';
import '../services/route_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

String _formatDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}  ${two(l.hour)}:${two(l.minute)}';
}

/// Uploads [route] and, on success, flags it uploaded in the offline store.
/// Returns the updated route (null on failure) and a message for the user.
Future<(RouteTrack?, String)> _uploadRoute(RouteTrack route) async {
  try {
    await RouteApi.upload(route);
    final updated = await RouteStore.markUploaded(route.id, DateTime.now());
    return (updated ?? route, 'Route uploaded to server.');
  } on RouteApiException catch (e) {
    return (null, e.message);
  }
}

/// Routes recorded and saved offline on this phone.
class SavedRoutesScreen extends StatefulWidget {
  const SavedRoutesScreen({super.key});

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  List<RouteTrack>? _routes;
  final _uploadingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routes = await RouteStore.load();
    if (mounted) setState(() => _routes = routes);
  }

  Future<void> _upload(RouteTrack route) async {
    setState(() => _uploadingIds.add(route.id));
    final (_, message) = await _uploadRoute(route);
    if (!mounted) return;
    setState(() => _uploadingIds.remove(route.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  List<RouteTrack> get _pending =>
      [for (final r in _routes ?? const <RouteTrack>[]) if (!r.isUploaded) r];

  /// Uploads every route that isn't on the server yet, one after another.
  Future<void> _uploadAll() async {
    final pending = _pending;
    if (pending.isEmpty) return;

    setState(() => _uploadingIds.addAll(pending.map((r) => r.id)));
    var done = 0;
    final failures = <String>[];
    for (final route in pending) {
      final (updated, message) = await _uploadRoute(route);
      if (updated != null) {
        done++;
      } else {
        failures.add(
          '${_formatDateTime(route.startedAt)} (${route.points.length} pts): '
          '$message',
        );
      }
      if (!mounted) return;
      setState(() => _uploadingIds.remove(route.id));
    }

    await _load();
    if (!mounted) return;
    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$done route${done == 1 ? '' : 's'} uploaded.'),
        ),
      );
      return;
    }
    // One line per failed route, so each route's own reason is visible.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$done uploaded, ${failures.length} failed'),
        content: SingleChildScrollView(
          child: Text(failures.join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(RouteTrack route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete route?'),
        content: const Text('This saved route will be removed from the phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RouteStore.delete(route.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final routes = _routes;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Saved routes'),
      bottomNavigationBar: routes == null || routes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: FilledButton.icon(
                  onPressed: _pending.isEmpty || _uploadingIds.isNotEmpty
                      ? null
                      : _uploadAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: Text(
                    _pending.isEmpty
                        ? 'All routes uploaded'
                        : 'Upload data (${_pending.length})',
                  ),
                ),
              ),
            ),
      body: routes == null
          ? const Center(child: CircularProgressIndicator())
          : routes.isEmpty
          ? const Center(child: Text('No saved routes yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.screen),
              itemCount: routes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final route = routes[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                      route.isUploaded
                          ? Icons.cloud_done_rounded
                          : Icons.route_rounded,
                      color: route.isUploaded ? const Color(0xFF2E7D32) : null,
                    ),
                    title: Text(_formatDateTime(route.startedAt)),
                    subtitle: Text(
                      '${formatDistance(route.distanceMeters)} · '
                      '${formatDuration(route.duration)} · '
                      '${route.points.length} points'
                      '${route.isUploaded ? ' · Uploaded' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_uploadingIds.contains(route.id))
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                          )
                        else if (!route.isUploaded)
                          IconButton(
                            tooltip: 'Upload online',
                            icon: const Icon(Icons.cloud_upload_outlined),
                            onPressed: () => _upload(route),
                          ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(route),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RouteViewScreen(route: route),
                        ),
                      );
                      // The route may have been uploaded on the next screen.
                      await _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// One saved route drawn on a map, with its raw JSON a tap away.
class RouteViewScreen extends StatefulWidget {
  const RouteViewScreen({super.key, required this.route});

  final RouteTrack route;

  @override
  State<RouteViewScreen> createState() => _RouteViewScreenState();
}

class _RouteViewScreenState extends State<RouteViewScreen> {
  static const _streetsTiles =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';

  late RouteTrack route = widget.route;
  bool _uploading = false;

  Future<void> _upload() async {
    setState(() => _uploading = true);
    final (updated, message) = await _uploadRoute(route);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (updated != null) route = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showJson(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(route.toJson());
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Route JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON copied')),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latLngs = [for (final p in route.points) p.latLng];
    final single = latLngs.length < 2;

    return Scaffold(
      appBar: GradientAppBar(
        title: _formatDateTime(route.startedAt),
        actions: [
          IconButton(
            tooltip: 'View JSON',
            icon: const Icon(Icons.data_object_rounded),
            onPressed: () => _showJson(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: latLngs.first,
              initialZoom: 17,
              initialCameraFit: single
                  ? null
                  : CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(latLngs),
                      padding: const EdgeInsets.all(48),
                      maxZoom: 18,
                    ),
            ),
            children: [
              TileLayer(
                urlTemplate: _streetsTiles,
                userAgentPackageName: 'com.example.my_first_app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: latLngs,
                    strokeWidth: 5,
                    color: const Color(0xFF1565C0),
                    borderStrokeWidth: 2,
                    borderColor: Colors.white,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: latLngs.first,
                    width: 44,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF2E7D32),
                      size: 44,
                    ),
                  ),
                  if (!single)
                    Marker(
                      point: latLngs.last,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFD32F2F),
                        size: 44,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: AppSpacing.screen,
            right: AppSpacing.screen,
            bottom: AppSpacing.screen,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${formatDistance(route.distanceMeters)}  ·  '
                      '${formatDuration(route.duration)}  ·  '
                      '${route.points.length} points',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: route.isUploaded || _uploading ? null : _upload,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              route.isUploaded
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_upload_rounded,
                            ),
                      label: Text(
                        route.isUploaded
                            ? 'Uploaded on '
                                  '${_formatDateTime(route.uploadedAt!)}'
                            : 'Upload online',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
