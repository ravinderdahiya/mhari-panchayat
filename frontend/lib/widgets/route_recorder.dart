import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/route_track.dart';
import '../navigation/app_navigation.dart';
import '../screens/saved_routes_screen.dart';
import '../services/route_store.dart';
import '../services/route_tracker.dart';
import '../theme/app_theme.dart';

enum _StopChoice { offline, discard }

/// Route icon + Start/Stop panel shown over the map. Place it in a
/// `Positioned` - it sizes itself to its content.
class RouteRecorderControl extends StatefulWidget {
  const RouteRecorderControl({super.key});

  @override
  State<RouteRecorderControl> createState() => _RouteRecorderControlState();
}

class _RouteRecorderControlState extends State<RouteRecorderControl> {
  final _tracker = RouteTracker.instance;
  Timer? _clock;
  bool _open = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTrackerChanged);
    _syncClock();
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTrackerChanged);
    _clock?.cancel();
    super.dispose();
  }

  void _onTrackerChanged() {
    if (!mounted) return;
    _syncClock();
    setState(() {});
  }

  /// Ticks once a second while recording so the elapsed time runs smoothly
  /// (GPS points only arrive every few seconds).
  void _syncClock() {
    if (_tracker.isRecording) {
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    final description = await showDialog<String>(
      context: context,
      builder: (_) => const _DescriptionDialog(),
    );
    if (description == null || !mounted) return;

    setState(() => _starting = true);
    final error = await _tracker.start(description);
    if (!mounted) return;
    setState(() => _starting = false);
    if (error != null) _snack(error);
  }

  Future<void> _stop() async {
    final track = _tracker.stop();
    if (track == null) {
      _snack('No location was captured, nothing to save.');
      return;
    }

    final choice = await showDialog<_StopChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveDialog(track: track),
    );
    if (!mounted) return;

    if (choice == _StopChoice.offline) {
      await RouteStore.save(track);
      if (!mounted) return;
      _snack('Route saved offline (${track.points.length} points).');
    } else {
      _snack('Route discarded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _tracker.isRecording;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open) ...[_buildPanel(recording), const SizedBox(height: 10)],
        FloatingActionButton(
          heroTag: 'route_recorder',
          tooltip: 'Record route',
          backgroundColor: recording ? const Color(0xFFD32F2F) : AppColors.background,
          foregroundColor: recording ? Colors.white : AppColors.primary,
          onPressed: () => setState(() => _open = !_open),
          child: Icon(recording ? Icons.fiber_manual_record : Icons.route_rounded),
        ),
      ],
    );
  }

  Widget _buildPanel(bool recording) {
    final labelStyle = GoogleFonts.poppins(
      fontSize: 11,
      color: AppColors.mutedText,
    );
    final valueStyle = GoogleFonts.poppins(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    );

    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: valueStyle),
          Text(label, style: labelStyle),
        ],
      ),
    );

    return Material(
      color: AppColors.background,
      elevation: 6,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              recording ? 'Recording route…' : 'Route recorder',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: recording ? const Color(0xFFD32F2F) : AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            if (recording) ...[
              Row(
                children: [
                  stat('Time', formatDuration(_tracker.elapsed)),
                  stat('Distance', formatDistance(_tracker.distanceMeters)),
                  stat('Points', '${_tracker.points.length}'),
                ],
              ),
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Press Start and walk. Your location is recorded every '
                  '${RouteTracker.interval.inSeconds} seconds and drawn as a line.',
                  style: labelStyle,
                ),
              ),
            FilledButton.icon(
              onPressed: _starting ? null : (recording ? _stop : _start),
              style: FilledButton.styleFrom(
                backgroundColor: recording
                    ? const Color(0xFFD32F2F)
                    : AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              icon: _starting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(recording ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(recording ? 'Stop' : 'Start'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => push(context, const SavedRoutesScreen()),
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Saved routes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks what the route is for before recording starts. The description is
/// required - Start stays blocked until something is typed.
class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog();

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start route'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description *',
            hintText: 'What is this route for?',
            border: OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Description is required'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start')),
      ],
    );
  }
}

class _SaveDialog extends StatelessWidget {
  const _SaveDialog({required this.track});

  final RouteTrack track;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Route finished'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (track.description.isNotEmpty) ...[
            Text(
              track.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '${formatDistance(track.distanceMeters)} · '
            '${formatDuration(track.duration)} · '
            '${track.points.length} points',
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.save_alt_rounded),
            title: const Text('Offline'),
            subtitle: const Text('Save as JSON on this phone'),
            onTap: () => Navigator.pop(context, _StopChoice.offline),
          ),
          const ListTile(
            enabled: false,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_upload_rounded),
            title: Text('Online'),
            subtitle: Text('Save to server - coming soon'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _StopChoice.discard),
          child: const Text('Discard'),
        ),
      ],
    );
  }
}
