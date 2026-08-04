enum ComplaintStatus {
  pending,
  assigned,
  accepted,
  inspection,
  workStarted,
  resolved,
  citizenVerification,
  closed,
  rejected,
}

extension ComplaintStatusWire on ComplaintStatus {
  String get wireValue => switch (this) {
    ComplaintStatus.pending => 'PENDING',
    ComplaintStatus.assigned => 'ASSIGNED',
    ComplaintStatus.accepted => 'ACCEPTED',
    ComplaintStatus.inspection => 'INSPECTION',
    ComplaintStatus.workStarted => 'WORK_STARTED',
    ComplaintStatus.resolved => 'RESOLVED',
    ComplaintStatus.citizenVerification => 'CITIZEN_VERIFICATION',
    ComplaintStatus.closed => 'CLOSED',
    ComplaintStatus.rejected => 'REJECTED',
  };

  static ComplaintStatus fromWire(String? value) {
    return switch (value) {
      'ASSIGNED' || 'Acknowledged' => ComplaintStatus.assigned,
      'ACCEPTED' => ComplaintStatus.accepted,
      'INSPECTION' || 'Surveyed' => ComplaintStatus.inspection,
      'WORK_STARTED' || 'In_Progress' => ComplaintStatus.workStarted,
      'RESOLVED' || 'Resolved' => ComplaintStatus.resolved,
      'CITIZEN_VERIFICATION' => ComplaintStatus.citizenVerification,
      'CLOSED' || 'Closed' => ComplaintStatus.closed,
      'REJECTED' || 'Rejected' => ComplaintStatus.rejected,
      _ => ComplaintStatus.pending,
    };
  }
}

class Complaint {
  const Complaint({
    required this.id,
    required this.complaintCode,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.village,
    required this.panchayat,
    this.district = '',
    this.tehsil = '',
    this.priority,
    this.department,
    this.assetType,
    this.category,
    required this.description,
    this.latitude,
    this.longitude,
    this.photoUrls = const [],
    this.resolutionPhotoUrls = const [],
    required this.status,
    this.citizenMobile,
    this.assignedOfficerId,
    this.assignedOfficerName,
    this.assignedOfficerDesignation,
    this.assignmentDate,
    this.resolvedAt,
    required this.createdAt,
  });

  final String id;

  /// Public human-readable ID shown to citizens and officers, e.g. COMP-0001.
  final String complaintCode;

  /// Foreign key (Survey/asset uuid) this complaint is permanently linked to.
  final String assetId;

  /// Human-readable asset code, e.g. "AST000001" — internal/admin use.
  final String assetCode;
  final String assetName;
  final String village;
  final String panchayat;
  final String district;
  final String tehsil;
  final String? priority;
  final String? department;
  final String? assetType;
  final String? category;
  final String description;
  final double? latitude;
  final double? longitude;
  final List<String> photoUrls;

  /// Officer "after fix" photos uploaded when marking the complaint resolved.
  final List<String> resolutionPhotoUrls;
  final ComplaintStatus status;
  final String? citizenMobile;
  final String? assignedOfficerId;
  final String? assignedOfficerName;
  final String? assignedOfficerDesignation;
  final DateTime? assignmentDate;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  String get trackingId {
    if (id.toUpperCase().startsWith('CMP-')) return id;
    final numeric = int.tryParse(id);
    final serial = numeric == null ? id : numeric.toString().padLeft(6, '0');
    return 'CMP-${createdAt.year}-$serial';
  }

  String get displayCode =>
      complaintCode.trim().isNotEmpty ? complaintCode : trackingId;

  String get displaySubject =>
      (category?.trim().isNotEmpty ?? false) ? category! : 'General Complaint';

  String get locationLabel {
    return [
      village,
      panchayat,
      tehsil,
      district,
    ].where((value) => value.trim().isNotEmpty).toSet().join(', ');
  }

  String get dateLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = createdAt.day.toString().padLeft(2, '0');
    return '$day ${months[createdAt.month - 1]} ${createdAt.year}';
  }
}
