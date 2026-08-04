class AssetType {
  const AssetType({
    required this.id,
    required this.name,
    required this.iconKey,
  });

  final String id;
  final String name;
  final String iconKey;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon_key': iconKey,
  };

  factory AssetType.fromJson(Map<String, dynamic> json) {
    return AssetType(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      iconKey: (json['icon_key'] ?? json['iconKey'])?.toString() ?? 'apartment',
    );
  }
}
