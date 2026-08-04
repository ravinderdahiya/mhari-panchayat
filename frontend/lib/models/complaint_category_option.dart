class ComplaintCategoryOption {
  const ComplaintCategoryOption({
    required this.id,
    required this.name,
    this.defaultPriorityId,
  });

  final int id;
  final String name;
  final int? defaultPriorityId;

  factory ComplaintCategoryOption.fromJson(Map<String, dynamic> json) {
    return ComplaintCategoryOption(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      defaultPriorityId: int.tryParse(
        json['defaultPriorityId']?.toString() ?? '',
      ),
    );
  }
}
