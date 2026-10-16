import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../navigation/app_navigation.dart';
import '../navigation/role_navigation.dart';
import '../services/app_version_service.dart';
import '../services/auth_service.dart';
import '../widgets/update_dialog.dart';
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
    // Runs alongside the splash delay, so it costs no extra waiting.
    final versionCheck = AppVersionService.check();
    final session = await AuthService.getSession();

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < SplashScreen.minDisplayDuration) {
      await Future<void>.delayed(SplashScreen.minDisplayDuration - elapsed);
    }

    final update = await versionCheck;
    if (!mounted || _hasFinished) return;

    if (update.status != UpdateStatus.ok) {
      // A forced update never returns here: the dialog can't be dismissed.
      await showUpdateDialog(context, update);
      if (!mounted || _hasFinished) return;
    }

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
        body: SizedBox(
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
