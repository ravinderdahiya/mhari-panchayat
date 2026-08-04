enum NotificationKind { submitted, assigned, resolved, rejected }

extension NotificationKindWire on NotificationKind {
  static NotificationKind fromWireValue(String? value) {
    switch (value) {
      case 'COMPLAINT_ASSIGNED':
        return NotificationKind.assigned;
      case 'COMPLAINT_RESOLVED':
        return NotificationKind.resolved;
      case 'COMPLAINT_REJECTED':
        return NotificationKind.rejected;
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
    required this.kind,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String complaintId;
  final NotificationKind kind;
  final String title;
  final String message;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      complaintId: json['complaintId'] as String? ?? '',
      kind: NotificationKindWire.fromWireValue(json['type'] as String?),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}
