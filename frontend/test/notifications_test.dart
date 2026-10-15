import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mhari_panchayat/models/app_notification.dart';
import 'package:mhari_panchayat/services/notification_center.dart';
import 'package:mhari_panchayat/widgets/notification_badge.dart';

void main() {
  group('AppNotification.fromJson', () {
    Map<String, dynamic> payload(String type, {String complaintId = '', String surveyId = ''}) => {
      'id': '7',
      'complaintId': complaintId,
      'assetSurveyId': surveyId,
      'type': type,
      'title': 'Survey returned for correction',
      'message': 'Hand Pump (Satrod) was returned for correction. Reason: blurry photo',
      'isRead': false,
      'createdAt': '2026-10-15T07:07:02+00:00',
    };

    test('maps every survey workflow type and keeps the survey id', () {
      const expected = {
        'SURVEY_REVIEW_NEEDED': NotificationKind.surveyReview,
        'SURVEY_RETURNED': NotificationKind.surveyReturned,
        'SURVEY_REJECTED': NotificationKind.surveyRejected,
        'SURVEY_APPROVED': NotificationKind.surveyApproved,
      };
      for (final entry in expected.entries) {
        final n = AppNotification.fromJson(payload(entry.key, surveyId: '17'));
        expect(n.kind, entry.value);
        expect(n.assetSurveyId, '17');
        expect(n.complaintId, isEmpty);
      }
    });

    test('complaint notifications are unchanged and carry no survey id', () {
      final n = AppNotification.fromJson(payload('COMPLAINT_RESOLVED', complaintId: '5'));
      expect(n.kind, NotificationKind.resolved);
      expect(n.complaintId, '5');
      expect(n.assetSurveyId, isEmpty);
    });

    test('copyWith(isRead) keeps the survey id', () {
      final n = AppNotification.fromJson(payload('SURVEY_REVIEW_NEEDED', surveyId: '9')).copyWith(isRead: true);
      expect(n.isRead, isTrue);
      expect(n.assetSurveyId, '9');
    });
  });

  group('NotificationBadgeIcon', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotificationBadgeIcon(icon: Icons.notifications_outlined))),
    );

    testWidgets('shows the unread count, caps it at 99+, hides it at zero', (tester) async {
      await pump(tester);

      NotificationCenter.instance.setUnread(0);
      await tester.pump();
      expect(find.text('0'), findsNothing);

      NotificationCenter.instance.setUnread(3);
      await tester.pump();
      expect(find.text('3'), findsOneWidget);

      NotificationCenter.instance.setUnread(250);
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);

      NotificationCenter.instance.setUnread(-4); // never negative
      await tester.pump();
      expect(NotificationCenter.instance.unread.value, 0);
    });
  });
}
