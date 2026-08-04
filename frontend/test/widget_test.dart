import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mhari_panchayat/app.dart';
import 'package:mhari_panchayat/models/user_role.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Panchayat app starts on splash screen', (tester) async {
    await tester.pumpWidget(const PanchayatApp());

    expect(find.text('Panchayat Grievance Redressal System'), findsOneWidget);
    expect(find.text('हरियाणा सरकार'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('Login screen opens when user is not logged in', (tester) async {
    await tester.pumpWidget(const PanchayatApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Panchayat Grievance System'), findsOneWidget);
    expect(find.text('Citizen'), findsOneWidget);
  });

  testWidgets('Dashboard opens when valid token exists', (tester) async {
    SharedPreferences.setMockInitialValues({
      'is_logged_in': true,
      'auth_token': 'pg_test_token',
      'user_role': UserRole.citizen.storageValue,
    });

    await tester.pumpWidget(const PanchayatApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('नमस्ते 👋'), findsOneWidget);
    expect(find.text('Panchayat Grievance System'), findsNothing);
  });
}
