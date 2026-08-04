class SurveyDepartment {
  const SurveyDepartment({required this.id, required this.name, this.code});

  final int id;
  final String name;
  final String? code;

  factory SurveyDepartment.fromJson(Map<String, dynamic> json) {
    return SurveyDepartment(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
    );
  }
}
