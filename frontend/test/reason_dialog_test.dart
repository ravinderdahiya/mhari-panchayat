import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhari_panchayat/screens/survey_review_detail_screen.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, ValueChanged<String?> onResult) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => onResult(
                  await showDialog<String>(
                    context: context,
                    builder: (_) => const ReasonDialog(
                      title: 'Return for correction',
                      actionLabel: 'Return',
                      actionColor: Colors.orange,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton actionButton(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Return'));

  testWidgets('Return stays disabled while the reason is empty, enables once something is typed', (tester) async {
    await openDialog(tester, (_) {});

    expect(actionButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(actionButton(tester).onPressed, isNull, reason: 'whitespace only is still empty');

    await tester.enterText(find.byType(TextField), 'Photo is blurry');
    await tester.pump();
    expect(actionButton(tester).onPressed, isNotNull);
  });

  testWidgets('tapping Return hands back the trimmed reason', (tester) async {
    String? result;
    await openDialog(tester, (value) => result = value);

    await tester.enterText(find.byType(TextField), '  Wrong location  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pumpAndSettle();

    expect(result, 'Wrong location');
  });

  testWidgets('Cancel returns nothing', (tester) async {
    String? result = 'untouched';
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
