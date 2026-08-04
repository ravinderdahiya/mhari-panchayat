import 'package:flutter/material.dart';

import 'navigation/navigator_key.dart';
import 'navigation/role_navigation.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'theme/app_theme.dart';

class PanchayatApp extends StatefulWidget {
  const PanchayatApp({super.key});

  @override
  State<PanchayatApp> createState() => _PanchayatAppState();
}

class _PanchayatAppState extends State<PanchayatApp> {
  final _deepLinks = DeepLinkService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _deepLinks.start());
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    super.dispose();
  }

  void _onSplashComplete(AuthSession? session) {
    final nextScreen = session != null && session.isValid
        ? dashboardForRole(session.role)
        : const LoginScreen();

    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      // No navigator to replace on - nothing for a deep link to race against
      // either, so unblock it rather than waiting on a signal that will never come.
      splashNavigationDone.value = true;
      return;
    }

    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => nextScreen),
    );
    splashNavigationDone.value = true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Mhari Panchayat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(onComplete: _onSplashComplete),
    );
  }
}
