import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mhari_panchayat/app.dart';
import 'package:mhari_panchayat/models/user_role.dart';
import 'package:mhari_panchayat/screens/citizen_shell.dart';
import 'package:mhari_panchayat/screens/login_screen.dart';
import 'package:mhari_panchayat/screens/splash_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The splash's version check reads this; without a mock it never
    // completes under the test binding and the app stays on the splash.
    PackageInfo.setMockInitialValues(
      appName: 'Mhari Panchayat',
      packageName: 'in.hsac.mharipanchayat',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('Panchayat app starts on splash screen', (tester) async {
    await tester.pumpWidget(const PanchayatApp());

    expect(find.byType(SplashScreen), findsOneWidget);

    // Past the 3s splash; pumpAndSettle would never return (looping animations).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('Login screen opens when user is not logged in', (tester) async {
    await tester.pumpWidget(const PanchayatApp());
    // Past the 3s splash; pumpAndSettle would never return (looping animations).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('Dashboard opens when valid token exists', (tester) async {
    SharedPreferences.setMockInitialValues({
      'is_logged_in': true,
      'auth_token': 'pg_test_token',
      'user_role': UserRole.citizen.storageValue,
    });

    await tester.pumpWidget(const PanchayatApp());
    // Past the 3s splash; pumpAndSettle would never return (looping animations).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.byType(CitizenShell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
