enum NotificationKind {
  submitted,
  assigned,
  resolved,
  rejected,
  // Asset-survey review workflow
  surveyReview,
  surveyReturned,
  surveyRejected,
  surveyApproved,
}

extension NotificationKindWire on NotificationKind {
  static NotificationKind fromWireValue(String? value) {
    switch (value) {
      case 'COMPLAINT_ASSIGNED':
        return NotificationKind.assigned;
      case 'COMPLAINT_RESOLVED':
        return NotificationKind.resolved;
      case 'COMPLAINT_REJECTED':
        return NotificationKind.rejected;
      case 'SURVEY_REVIEW_NEEDED':
        return NotificationKind.surveyReview;
      case 'SURVEY_RETURNED':
        return NotificationKind.surveyReturned;
      case 'SURVEY_REJECTED':
        return NotificationKind.surveyRejected;
      case 'SURVEY_APPROVED':
        return NotificationKind.surveyApproved;
      case 'COMPLAINT_SUBMITTED':
      default:
        return NotificationKind.submitted;
    }
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.complaintId,
    this.assetSurveyId = '',
    required this.kind,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String complaintId;

  /// Set for asset-survey notifications (empty for complaint ones).
  final String assetSurveyId;
  final NotificationKind kind;
  final String title;
  final String message;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: _asString(json['id']),
      complaintId: _asString(json['complaintId'] ?? json['complaint_id']),
      assetSurveyId: _asString(json['assetSurveyId'] ?? json['asset_survey_id']),
      kind: NotificationKindWire.fromWireValue(json['type'] as String?),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['created_at'] ?? '') as String? ?? '',
      ),
    );
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      complaintId: complaintId,
      assetSurveyId: assetSurveyId,
      kind: kind,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
