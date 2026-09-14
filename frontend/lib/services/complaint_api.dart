import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../config/api_config.dart';
import '../models/complaint.dart';
import '../models/complaint_category_option.dart';
import '../models/complaint_form_option.dart';
import 'auth_service.dart';
import 'session_guard.dart';

class ComplaintApiException implements Exception {
  ComplaintApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthenticated =>
      statusCode == 401 || message.trim().toLowerCase() == 'unauthenticated';

  @override
  String toString() => message;
}

class OfficerReportCategory {
  const OfficerReportCategory({required this.name, required this.percent});

  final String name;
  final double percent;
}

class OfficerReportSummary {
  const OfficerReportSummary({
    required this.resolved,
    this.averageResolutionDays,
    required this.categories,
  });

  final int resolved;
  final double? averageResolutionDays;
  final List<OfficerReportCategory> categories;
}

/// Talks to `/api/complaints` on the Gram Samadhan backend.
class ComplaintApi {
  ComplaintApi._();

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/complaints$path');

  /// Submits a complaint against a confirmed surveyed asset. The citizen
  /// never picks or sees the asset's raw ID beyond this point — it's just
  /// passed through internally.
  static Future<Complaint> submit({
    required int departmentId,
    required int assetTypeId,
    int? districtId,
    int? tehsilId,
    int? villageId,
    String? locationState,
    String? locationDistrict,
    String? locationTehsil,
    String? locationVillage,
    String? locationBlock,
    int? categoryId,
    required int priorityId,
    required String description,
    double? latitude,
    double? longitude,
    List<Uint8List> photos = const [],
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw ComplaintApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      final request = http.MultipartRequest('POST', _uri(''))
        ..headers['Authorization'] = 'Bearer ${session.token}'
        ..fields.addAll({
          'department_id': departmentId.toString(),
          'asset_type_id': assetTypeId.toString(),
          if (districtId != null) 'district_id': districtId.toString(),
          if (tehsilId != null) 'tehsil_id': tehsilId.toString(),
          if (villageId != null) 'village_id': villageId.toString(),
          if (locationState?.trim().isNotEmpty ?? false)
            'location_state': locationState!.trim(),
          if (locationDistrict?.trim().isNotEmpty ?? false)
            'location_district': locationDistrict!.trim(),
          if (locationTehsil?.trim().isNotEmpty ?? false)
            'location_tehsil': locationTehsil!.trim(),
          if (locationVillage?.trim().isNotEmpty ?? false)
            'location_village': locationVillage!.trim(),
          if (locationBlock?.trim().isNotEmpty ?? false)
            'location_block': locationBlock!.trim(),
          if (categoryId != null) 'category_id': categoryId.toString(),
          'priority_id': priorityId.toString(),
          'description': description,
          if (latitude != null) 'lat': latitude.toString(),
          if (longitude != null) 'long': longitude.toString(),
        });

      if (photos.isNotEmpty) {
        // Legacy backends still require the singular `photo` field.
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            photos.first,
            filename: 'complaint_photo_0.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        for (var i = 0; i < photos.length && i < 5; i++) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'photos[$i]',
              photos[i],
              filename: 'complaint_photo_$i.jpg',
              contentType: MediaType('image', 'jpeg'),
            ),
          );
        }
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw ComplaintApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    final body = _decode(response);
    await _throwIfError(
      response,
      body,
      'शिकायत दर्ज नहीं हो पाई। पुनः प्रयास करें।',
    );

    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  static Future<ComplaintFormOptions> getFormOptions({
    int? districtId,
    int? tehsilId,
  }) async {
    final query = <String, String>{
      if (districtId != null) 'district_id': districtId.toString(),
      if (tehsilId != null) 'tehsil_id': tehsilId.toString(),
    };
    final body = await _get(
      _uri(
        '/form-options',
      ).replace(queryParameters: query.isEmpty ? null : query),
      'Complaint form data could not be loaded.',
    );
    return ComplaintFormOptions.fromJson(body);
  }

  static Future<List<ComplaintCategoryOption>> getCategories({
    int? assetTypeId,
    int? departmentId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/complaint-categories')
        .replace(
          queryParameters: assetTypeId == null
              ? null
              : {
                  'asset_type_id': assetTypeId.toString(),
                  if (departmentId != null)
                    'department_id': departmentId.toString(),
                },
        );
    final body = await _get(uri, 'Complaint categories could not be loaded.');
    final categories = body['categories'] as List<dynamic>? ?? const [];
    return categories
        .map(
          (item) => ComplaintCategoryOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((category) => category.id > 0 && category.name.isNotEmpty)
        .toList();
  }

  static Future<OfficerReportSummary> getOfficerReports() async {
    final body = await _get(
      _uri('/mobile-reports'),
      'Reports could not be loaded.',
    );
    final reports = body['reports'] as Map<String, dynamic>? ?? const {};
    final categoryRows = reports['categories'] as List<dynamic>? ?? const [];
    return OfficerReportSummary(
      resolved: (reports['resolved'] as num?)?.toInt() ?? 0,
      averageResolutionDays: (reports['averageResolutionDays'] as num?)
          ?.toDouble(),
      categories: categoryRows
          .map((item) {
            final row = Map<String, dynamic>.from(item as Map);
            return OfficerReportCategory(
              name: row['name']?.toString() ?? '',
              percent: (row['percent'] as num?)?.toDouble() ?? 0,
            );
          })
          .where((row) => row.name.isNotEmpty)
          .toList(),
    );
  }

  /// Fetches all complaints raised by the signed-in citizen, newest first.
  static Future<List<Complaint>> getMine() async {
    final body = await _get(
      _uri(''),
      'शिकायतें लोड नहीं हो पाईं। पुनः प्रयास करें।',
    );
    final complaints = body['complaints'] as List<dynamic>? ?? const [];
    return complaints
        .map((item) => _fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Fetches the latest state of a previously submitted complaint.
  static Future<Complaint> getById(String id) async {
    final body = await _get(
      _uri('/$id'),
      'शिकायत लोड नहीं हो पाई। पुनः प्रयास करें।',
    );
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Officer-only: the full complaint queue — every officer sees every
  /// complaint so any of them can self-accept or (pre-acceptance) reassign.
  static Future<List<Complaint>> getOfficerQueue() async {
    final body = await _get(
      _uri('/officer-queue'),
      'शिकायतें लोड नहीं हो पाईं। पुनः प्रयास करें।',
    );
    final complaints = body['complaints'] as List<dynamic>? ?? const [];
    return complaints
        .map((item) => _fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Officer-only: self-accepts a Pending/Reopened complaint (the queue's
  /// "Accept" button). Backend route: PATCH /complaints/{id}/acknowledge.
  static Future<Complaint> acknowledge(String id, String assignedToId) async {
    final body = await _patch(_uri('/$id/acknowledge'), {
      'assigned_to_id': assignedToId,
    }, 'शिकायत स्वीकार नहीं हो पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Officer-only: reassigns an already-accepted complaint to a different
  /// officer. Backend route: PATCH /complaints/{id}/transfer.
  static Future<Complaint> transfer(String id, String toUserId) async {
    final body = await _patch(_uri('/$id/transfer'), {
      'to_user_id': toUserId,
    }, 'शिकायत असाइन नहीं हो पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Drives the complaint through its status pipeline. Used by both
  /// officers (ACCEPTED/INSPECTION/WORK_STARTED/RESOLVED/REJECTED) and
  /// citizens (CLOSED / reopen back to WORK_STARTED) — the backend
  /// validates who's allowed to make each specific transition.
  ///
  /// When [status] is `RESOLVED`, [resolutionPhotos] must contain at least
  /// one image (multipart upload of the officer's after-fix evidence).
  /// Officer-only: submits one field-inspection stage. Backend route:
  /// PATCH /complaints/{id}/survey. `stage` is 'Before' (Acknowledged ->
  /// Surveyed), 'During' or 'After' (-> In_Progress); the matching photo
  /// field (before/during/after_photo) is attached when [photo] is given.
  static Future<Complaint> survey(
    String id, {
    required String stage,
    String? notes,
    Uint8List? photo,
  }) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw ComplaintApiException('कृपया पहले लॉगिन करें');
    }

    final photoField = switch (stage) {
      'Before' => 'before_photo',
      'During' => 'during_photo',
      _ => 'after_photo',
    };

    late final http.Response response;
    try {
      final request = http.MultipartRequest('PATCH', _uri('/$id/survey'))
        ..headers['Authorization'] = 'Bearer ${session.token}'
        ..fields['stage'] = stage;
      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }
      if (photo != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            photoField,
            photo,
            filename: '$photoField.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw ComplaintApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    final body = _decode(response);
    await _throwIfError(
      response,
      body,
      'फील्ड सर्वे सबमिट नहीं हो पाया। पुनः प्रयास करें।',
    );
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Officer-only: marks an In_Progress/Surveyed complaint Resolved.
  /// Backend route: PATCH /complaints/{id}/resolve.
  static Future<Complaint> resolve(String id, {String? notes}) async {
    final body = await _patch(_uri('/$id/resolve'), {
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }, 'शिकायत हल के रूप में चिह्नित नहीं हो पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Rejects a complaint at any non-terminal status. Backend route:
  /// PATCH /complaints/{id}/reject.
  static Future<Complaint> reject(String id, {required String reason}) async {
    final body = await _patch(_uri('/$id/reject'), {
      'reason': reason,
    }, 'शिकायत अस्वीकार नहीं हो पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Citizen-only: rates and closes a Resolved complaint. Backend route:
  /// PATCH /complaints/{id}/rate.
  static Future<Complaint> rate(
    String id, {
    required int rating,
    String? feedback,
  }) async {
    final body = await _patch(_uri('/$id/rate'), {
      'rating': rating,
      if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
    }, 'रेटिंग सबमिट नहीं हो पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  /// Citizen-only: reopens a Closed complaint. Backend route:
  /// PATCH /complaints/{id}/reopen.
  static Future<Complaint> reopen(String id, {required String reason}) async {
    final body = await _patch(_uri('/$id/reopen'), {
      'reason': reason,
    }, 'शिकायत फिर से नहीं खुल पाई। पुनः प्रयास करें।');
    final complaint = body['complaint'] as Map<String, dynamic>? ?? const {};
    return _fromJson(complaint);
  }

  static Future<Map<String, dynamic>> _get(
    Uri uri,
    String errorFallback,
  ) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw ComplaintApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${session.token}'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ComplaintApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    final body = _decode(response);
    await _throwIfError(response, body, errorFallback);
    return body;
  }

  static Future<Map<String, dynamic>> _patch(
    Uri uri,
    Map<String, dynamic> payload,
    String errorFallback,
  ) async {
    final session = await AuthService.getSession();
    if (session == null || !session.isValid) {
      throw ComplaintApiException('कृपया पहले लॉगिन करें');
    }

    late final http.Response response;
    try {
      response = await http
          .patch(
            uri,
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ComplaintApiException(
        'Server से कनेक्ट नहीं हो पाया। कृपया पुनः प्रयास करें।',
      );
    }

    final body = _decode(response);
    await _throwIfError(response, body, errorFallback);
    return body;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _throwIfError(
    http.Response response,
    Map<String, dynamic> body,
    String fallback,
  ) async {
    if (response.statusCode == 401) {
      await SessionGuard.handleUnauthorized();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ComplaintApiException(
        body['message'] as String? ?? fallback,
        statusCode: response.statusCode,
      );
    }
  }

  static Complaint _fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse(
          json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '',
        ) ??
        DateTime.now();
    final resolvedAt = DateTime.tryParse(
      json['resolved_at']?.toString() ?? json['resolvedAt']?.toString() ?? '',
    );
    final assignmentDate = DateTime.tryParse(
      json['assignment_date']?.toString() ??
          json['assignmentDate']?.toString() ??
          '',
    );
    final asset = json['asset'] as Map<String, dynamic>? ?? const {};
    final assignedOfficer =
        (json['assigned_to'] ?? json['assignedOfficer'])
            as Map<String, dynamic>?;
    final citizen = (json['user'] ?? json['citizen']) as Map<String, dynamic>?;
    final category = json['category'];
    final priority = json['priority'];
    final department = json['department'];
    final assetType = json['asset_type'];
    final district = json['district'];
    final tehsil = json['tehsil'];
    final issuePhotos = json['issue_photo_urls'] as List<dynamic>?;
    final rawPhotos = <dynamic>[
      if (issuePhotos != null && issuePhotos.isNotEmpty)
        ...issuePhotos
      else ...[
        ...(json['photoUrls'] as List<dynamic>? ?? const []),
        json['before_photo_url'],
      ],
    ];
    final photoUrls = rawPhotos
        .where((value) => value != null && value.toString().isNotEmpty)
        .map((value) => _mobileUrl(value.toString()))
        .toSet()
        .toList();
    final resolutionPhotoUrls = <String>{
      ...(json['resolutionPhotoUrls'] as List<dynamic>? ?? const []).map(
        (p) => p.toString().startsWith('http')
            ? _mobileUrl(p.toString())
            : '${ApiConfig.baseUrl}$p',
      ),
      if (json['during_photo_url'] != null &&
          json['during_photo_url'].toString().isNotEmpty)
        _mobileUrl(json['during_photo_url'].toString()),
      if (json['after_photo_url'] != null &&
          json['after_photo_url'].toString().isNotEmpty)
        _mobileUrl(json['after_photo_url'].toString()),
    }.toList();

    return Complaint(
      id: json['id']?.toString() ?? '',
      complaintCode:
          json['complaintCode']?.toString() ??
          json['complaint_code']?.toString() ??
          json['code']?.toString() ??
          '',
      assetId: json['assetId']?.toString() ?? '',
      assetCode: asset['assetId'] as String? ?? '',
      assetName: asset['assetName'] as String? ?? '',
      village: json['village']?.toString() ?? asset['village'] as String? ?? '',
      panchayat:
          json['panchayat']?.toString() ?? asset['panchayat'] as String? ?? '',
      district: district is Map ? district['name']?.toString() ?? '' : '',
      tehsil: tehsil is Map ? tehsil['name']?.toString() ?? '' : '',
      block: json['location_block']?.toString() ?? '',
      priority: priority is Map ? priority['name']?.toString() : null,
      department: department is Map ? department['name']?.toString() : null,
      assetType: assetType is Map ? assetType['name']?.toString() : null,
      category: category is Map
          ? category['name']?.toString()
          : category?.toString(),
      description: json['description'] as String? ?? '',
      latitude: ((json['lat'] ?? json['latitude']) as num?)?.toDouble(),
      longitude: ((json['long'] ?? json['longitude']) as num?)?.toDouble(),
      photoUrls: photoUrls,
      resolutionPhotoUrls: resolutionPhotoUrls,
      status: ComplaintStatusWire.fromWire(json['status'] as String?),
      citizenMobile: citizen?['mobile']?.toString(),
      assignedOfficerId: assignedOfficer?['id']?.toString(),
      assignedOfficerName:
          assignedOfficer?['name']?.toString() ??
          assignedOfficer?['username']?.toString(),
      assignedOfficerDesignation: assignedOfficer?['designation']?.toString(),
      assignmentDate: assignmentDate,
      resolvedAt: resolvedAt,
      createdAt: createdAt,
    );
  }

  /// Stored photo URLs may have been baked in with the wrong host (an old
  /// backend bug returned internal addresses like `127.0.0.1:8083`), so this
  /// always re-points to the API currently in use. If the backend is
  /// deployed under a sub-path (e.g. `/mhari-panchayat`) and already
  /// generated a fully-correct absolute URL, [ApiConfig.baseUrl]'s own
  /// sub-path is stripped from the extracted path first so it isn't doubled.
  static String _mobileUrl(String value) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final basePath = base.path.isEmpty || base.path == '/' ? '' : base.path;

    final parsed = Uri.tryParse(value);
    var path = parsed != null && parsed.hasScheme
        ? (parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path)
        : (value.startsWith('/') ? value : '/$value');

    if (basePath.isNotEmpty && path.startsWith(basePath)) {
      path = path.substring(basePath.length);
    }

    return '${base.scheme}://${base.authority}$basePath$path';
  }
}
