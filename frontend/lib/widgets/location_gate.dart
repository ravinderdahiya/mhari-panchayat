import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Blocks [child] behind a full-screen prompt until device location
/// services (and permission) are turned on. Rechecks automatically when
/// the app resumes, so returning from system settings updates the view.
class LocationGate extends StatefulWidget {
  const LocationGate({super.key, required this.child});

  final Widget child;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _serviceEnabled = false;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permissionGranted = false;

    if (serviceEnabled) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      permissionGranted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }

    if (!mounted) return;
    setState(() {
      _serviceEnabled = serviceEnabled;
      _permissionGranted = permissionGranted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_serviceEnabled) {
      return _LocationBlockedView(
        title: 'Location is turned off',
        message:
            'Location services are disabled. Please enable location services to continue.',
        buttonLabel: 'Enable Location',
        onPressed: () async {
          await Geolocator.openLocationSettings();
          _check();
        },
      );
    }

    if (!_permissionGranted) {
      return _LocationBlockedView(
        title: 'Location permission needed',
        message:
            'Please allow location access so nearby complaints and services can be shown.',
        buttonLabel: 'Grant Permission',
        onPressed: _check,
      );
    }

    return widget.child;
  }
}

class _LocationBlockedView extends StatelessWidget {
  const _LocationBlockedView({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.greyBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_off_rounded,
                size: 56,
                color: AppColors.rejectedText,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF212121),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
