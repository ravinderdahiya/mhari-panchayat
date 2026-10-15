import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../navigation/app_navigation.dart';
import '../navigation/role_navigation.dart';
import '../services/auth_service.dart';
import '../utils/responsive.dart';
import 'login_screen.dart';

typedef SplashCompleteCallback = void Function(AuthSession? session);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final SplashCompleteCallback? onComplete;

  static const Duration minDisplayDuration = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isBootstrapping = false;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isBootstrapping || _hasFinished) return;
    _isBootstrapping = true;

    final startedAt = DateTime.now();
    final session = await AuthService.getSession();

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < SplashScreen.minDisplayDuration) {
      await Future<void>.delayed(SplashScreen.minDisplayDuration - elapsed);
    }

    if (!mounted || _hasFinished) return;
    _hasFinished = true;
    _finish(session);
  }

  void _finish(AuthSession? session) {
    if (widget.onComplete != null) {
      widget.onComplete!(session);
      return;
    }

    final nextScreen = session != null && session.isValid
        ? dashboardForSession(session)
        : const LoginScreen();
    pushReplacement(context, nextScreen);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: context.isTablet
            ? const _TabletSplashPoster()
            : SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Image.asset(
            'assets/images/splash_poster.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Tablet-only splash: the tall phone poster would be heavily cropped by
/// `BoxFit.cover` on a tablet, so show it whole (`contain`) over a blurred,
/// full-bleed copy of itself so the screen edges are still filled.
class _TabletSplashPoster extends StatelessWidget {
  const _TabletSplashPoster();

  static const _asset = 'assets/images/splash_poster.png';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Image.asset(_asset, fit: BoxFit.cover),
        ),
        ColoredBox(color: Colors.white.withValues(alpha: 0.35)),
        Image.asset(_asset, fit: BoxFit.contain),
      ],
    );
  }
}
