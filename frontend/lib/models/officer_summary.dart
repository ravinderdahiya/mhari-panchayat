class OfficerSummary {
  const OfficerSummary({
    required this.id,
    required this.name,
    required this.staffId,
    this.department,
    this.district,
    this.block,
    this.panchayat,
    this.designation,
  });

  final String id;
  final String name;
  final String staffId;
  final String? department;
  final String? district;
  final String? block;
  final String? panchayat;
  final String? designation;

  factory OfficerSummary.fromJson(Map<String, dynamic> json) {
    return OfficerSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Officer',
      staffId: json['staffId'] as String? ?? '',
      department: json['department'] as String?,
      district: json['district'] as String?,
      block: json['block'] as String?,
      panchayat: json['panchayat'] as String?,
      designation: json['designation'] as String?,
    );
  }
}
