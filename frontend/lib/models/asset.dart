import 'survey.dart';

/// Lean shape used for map markers — matches `GET /api/assets`.
class AssetSummary {
  const AssetSummary({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.assetTypeId,
    this.assetTypeName,
    this.iconKey,
    this.latitude,
    this.longitude,
    required this.condition,
  });

  final String id;
  final String assetId;
  final String assetName;
  final String assetTypeId;
  final String? assetTypeName;
  final String? iconKey;
  final double? latitude;
  final double? longitude;
  final SurveyCondition condition;

  factory AssetSummary.fromJson(Map<String, dynamic> json) {
    return AssetSummary(
      id: json['id'] as String? ?? '',
      assetId: json['assetId'] as String? ?? '',
      assetName: json['assetName'] as String? ?? '',
      assetTypeId: json['assetTypeId'] as String? ?? '',
      assetTypeName: json['assetTypeName'] as String?,
      iconKey: json['iconKey'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      condition: SurveyConditionLabel.fromWireValue(
        json['condition'] as String?,
      ),
    );
  }
}

/// A nearby search result — an `AssetSummary` plus the distance from the
/// citizen's current GPS position. Matches `GET /api/assets/nearby`.
class AssetNearby extends AssetSummary {
  const AssetNearby({
    required super.id,
    required super.assetId,
    required super.assetName,
    required super.assetTypeId,
    super.assetTypeName,
    super.iconKey,
    super.latitude,
    super.longitude,
    required super.condition,
    required this.distanceMeters,
  });

  final int distanceMeters;

  factory AssetNearby.fromJson(Map<String, dynamic> json) {
    final summary = AssetSummary.fromJson(json);
    return AssetNearby(
      id: summary.id,
      assetId: summary.assetId,
      assetName: summary.assetName,
      assetTypeId: summary.assetTypeId,
      assetTypeName: summary.assetTypeName,
      iconKey: summary.iconKey,
      latitude: summary.latitude,
      longitude: summary.longitude,
      condition: summary.condition,
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full shape used by the Asset Details screen — matches `GET /api/assets/:id`.
class AssetDetail {
  const AssetDetail({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.assetTypeId,
    this.assetTypeName,
    this.iconKey,
    required this.district,
    required this.block,
    required this.panchayat,
    required this.village,
    this.latitude,
    this.longitude,
    this.photoUrls = const [],
    this.description,
    required this.condition,
    required this.surveyDate,
    required this.totalComplaints,
    required this.resolvedCount,
    required this.pendingCount,
  });

  final String id;
  final String assetId;
  final String assetName;
  final String assetTypeId;
  final String? assetTypeName;
  final String? iconKey;
  final String district;
  final String block;
  final String panchayat;
  final String village;
  final double? latitude;
  final double? longitude;
  final List<String> photoUrls;
  final String? description;
  final SurveyCondition condition;
  final DateTime surveyDate;
  final int totalComplaints;
  final int resolvedCount;
  final int pendingCount;

  factory AssetDetail.fromJson(Map<String, dynamic> json) {
    final photos = json['photoUrls'] as List<dynamic>? ?? const [];
    return AssetDetail(
      id: json['id'] as String? ?? '',
      assetId: json['assetId'] as String? ?? '',
      assetName: json['assetName'] as String? ?? '',
      assetTypeId: json['assetTypeId'] as String? ?? '',
      assetTypeName: json['assetTypeName'] as String?,
      iconKey: json['iconKey'] as String?,
      district: json['district'] as String? ?? '',
      block: json['block'] as String? ?? '',
      panchayat: json['panchayat'] as String? ?? '',
      village: json['village'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      photoUrls: photos.map((e) => e as String).toList(),
      description: json['description'] as String?,
      condition: SurveyConditionLabel.fromWireValue(
        json['condition'] as String?,
      ),
      surveyDate:
          DateTime.tryParse(json['surveyDate'] as String? ?? '') ??
          DateTime.now(),
      totalComplaints: (json['totalComplaints'] as num?)?.toInt() ?? 0,
      resolvedCount: (json['resolvedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
