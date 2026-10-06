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

/// What the user picked in the recorder panel; handled after the panel closes.
enum _PanelAction { stop, savedRoutes }

/// Route icon over the map. Tapping it opens the recorder panel as a dialog in
/// the centre of the screen. Place it in a `Positioned` - it sizes itself.
class RouteRecorderControl extends StatefulWidget {
  const RouteRecorderControl({super.key});

  @override
  State<RouteRecorderControl> createState() => _RouteRecorderControlState();
}

class _RouteRecorderControlState extends State<RouteRecorderControl> {
  final _tracker = RouteTracker.instance;
  bool _busy = false; // a panel / dialog flow is in progress - ignore extra taps

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTrackerChanged);
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTrackerChanged);
    super.dispose();
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPanel() async {
    if (_busy) return;
    _busy = true;
    try {
      // Tapping outside the card or the X pops with null = just close.
      final action = await showDialog<_PanelAction>(
        context: context,
        builder: (_) => _RecorderPanelDialog(tracker: _tracker, onStart: _start),
      );
      if (action == null || !mounted) return;

      switch (action) {
        case _PanelAction.stop:
          await _stop();
        case _PanelAction.savedRoutes:
          push(context, const SavedRoutesScreen());
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _start() async {
    final description = await showDialog<String>(
      context: context,
      builder: (_) => const _DescriptionDialog(),
    );
    if (description == null || !mounted) return;

    final error = await _tracker.start(description);
    if (!mounted) return;
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

    return FloatingActionButton(
      heroTag: 'route_recorder',
      tooltip: 'Record route',
      backgroundColor: recording ? const Color(0xFFD32F2F) : AppColors.background,
      foregroundColor: recording ? Colors.white : AppColors.primary,
      onPressed: _openPanel,
      child: Icon(recording ? Icons.fiber_manual_record : Icons.route_rounded),
    );
  }
}

/// The Start/Stop panel, shown centred with a close (X) button. It follows the
/// tracker live (time / distance / points while recording) and hands the chosen
/// action back to the caller, so no recording logic lives here.
class _RecorderPanelDialog extends StatefulWidget {
  const _RecorderPanelDialog({required this.tracker, required this.onStart});

  final RouteTracker tracker;

  /// Asks for the description and starts recording. The panel stays open while
  /// this runs and then simply switches to its "Recording route…" view.
  final Future<void> Function() onStart;

  @override
  State<_RecorderPanelDialog> createState() => _RecorderPanelDialogState();
}

class _RecorderPanelDialogState extends State<_RecorderPanelDialog> {
  Timer? _clock;
  bool _starting = false;

  RouteTracker get _tracker => widget.tracker;

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

  Future<void> _handleStart() async {
    setState(() => _starting = true);
    try {
      await widget.onStart();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _tracker.isRecording;
    final labelStyle = GoogleFonts.poppins(
      fontSize: 12,
      color: AppColors.mutedText,
    );
    final valueStyle = GoogleFonts.poppins(
      fontSize: 16,
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

    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card + 6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recording ? 'Recording route…' : 'Route recorder',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: recording
                            ? const Color(0xFFD32F2F)
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: AppColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (recording) ...[
                Row(
                  children: [
                    stat('Time', formatDuration(_tracker.elapsed)),
                    stat('Distance', formatDistance(_tracker.distanceMeters)),
                    stat('Points', '${_tracker.points.length}'),
                  ],
                ),
                const SizedBox(height: 16),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Press Start and walk. Your location is recorded every '
                    '${RouteTracker.interval.inSeconds} seconds and drawn as a line.',
                    style: labelStyle,
                  ),
                ),
              FilledButton.icon(
                onPressed: _starting
                    ? null
                    : recording
                    ? () => Navigator.of(context).pop(_PanelAction.stop)
                    : _handleStart,
                style: FilledButton.styleFrom(
                  backgroundColor: recording
                      ? const Color(0xFFD32F2F)
                      : AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                icon: Icon(
                  recording ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(recording ? 'Stop' : 'Start'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_PanelAction.savedRoutes),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Saved routes'),
              ),
            ],
          ),
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
