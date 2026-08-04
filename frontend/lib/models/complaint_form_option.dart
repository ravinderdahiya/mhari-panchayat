import 'complaint_category_option.dart';

class ComplaintNamedOption {
  const ComplaintNamedOption({required this.id, required this.name});

  final int id;
  final String name;

  factory ComplaintNamedOption.fromJson(Map<String, dynamic> json) {
    return ComplaintNamedOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class ComplaintPriorityOption extends ComplaintNamedOption {
  const ComplaintPriorityOption({
    required super.id,
    required super.name,
    required this.level,
  });

  final int level;

  factory ComplaintPriorityOption.fromJson(Map<String, dynamic> json) {
    return ComplaintPriorityOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      level: int.tryParse(json['level']?.toString() ?? '') ?? 0,
    );
  }
}

class ComplaintVillageOption extends ComplaintNamedOption {
  const ComplaintVillageOption({
    required super.id,
    required super.name,
    required this.panchayatId,
    required this.panchayatName,
    required this.blockId,
    required this.blockName,
  });

  final int panchayatId;
  final String panchayatName;
  final int blockId;
  final String blockName;

  factory ComplaintVillageOption.fromJson(Map<String, dynamic> json) {
    return ComplaintVillageOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      panchayatId: int.tryParse(json['panchayatId']?.toString() ?? '') ?? 0,
      panchayatName: json['panchayatName']?.toString() ?? '',
      blockId: int.tryParse(json['blockId']?.toString() ?? '') ?? 0,
      blockName: json['blockName']?.toString() ?? '',
    );
  }
}

class ComplaintFormOptions {
  const ComplaintFormOptions({
    required this.districts,
    required this.tehsils,
    required this.villages,
    required this.categories,
    required this.priorities,
  });

  final List<ComplaintNamedOption> districts;
  final List<ComplaintNamedOption> tehsils;
  final List<ComplaintVillageOption> villages;
  final List<ComplaintCategoryOption> categories;
  final List<ComplaintPriorityOption> priorities;

  factory ComplaintFormOptions.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) {
      return (json[key] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return ComplaintFormOptions(
      districts: rows('districts')
          .map(ComplaintNamedOption.fromJson)
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(),
      tehsils: rows('tehsils')
          .map(ComplaintNamedOption.fromJson)
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(),
      villages: rows('villages')
          .map(ComplaintVillageOption.fromJson)
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(),
      categories: rows('categories')
          .map(ComplaintCategoryOption.fromJson)
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(),
      priorities: rows('priorities')
          .map(ComplaintPriorityOption.fromJson)
          .where((item) => item.id > 0 && item.name.isNotEmpty)
          .toList(),
    );
  }
}

class ComplaintLocationSelection {
  const ComplaintLocationSelection({
    required this.district,
    required this.tehsil,
    required this.village,
  });

  final ComplaintNamedOption district;
  final ComplaintNamedOption tehsil;
  final ComplaintVillageOption village;
}
