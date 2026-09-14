enum UserRole { citizen, officer, survey, gramSachiv, cplo }

extension UserRoleStorage on UserRole {
  String get storageValue => name;

  static UserRole? fromStorage(String? value) {
    if (value == null) return null;
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  /// Maps the backend `users.role` string onto the field-app shell.
  /// CPLO gets Home / Map / Tasks / Profile; surveyor stays on asset survey.
  static UserRole fromServerRole(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    return switch (key) {
      'citizen' => UserRole.citizen,
      'gram_sachiv' => UserRole.gramSachiv,
      'cplo' => UserRole.cplo,
      'surveyor' || 'engineer' => UserRole.survey,
      _ => UserRole.officer,
    };
  }
}

/// Display copy for the field survey shell. CPLO and Surveyor share the
/// same screens; only the identity labels differ.
class FieldStaffCopy {
  static String _key(String? serverRole) =>
      (serverRole ?? '').trim().toLowerCase();

  static bool isCplo(String? serverRole) => _key(serverRole) == 'cplo';

  static String roleLabel(String? serverRole) {
    return switch (_key(serverRole)) {
      'cplo' => 'CPLO',
      'surveyor' || 'engineer' => 'Surveyor',
      '' => '—',
      final key => key.replaceAll('_', ' '),
    };
  }

  static String profileFallbackName(String? serverRole) =>
      isCplo(serverRole) ? 'CPLO' : 'Surveyor';

  static String profileSubtitle(String? serverRole) => switch (_key(serverRole)) {
    'cplo' => 'CPLO / पंचायत स्तर अधिकारी',
    'surveyor' || 'engineer' => 'Field Asset Survey',
    '' => '',
    _ => 'Field Asset Survey',
  };

  static String surveyTitle(String? serverRole) =>
      isCplo(serverRole) ? 'CPLO Survey' : 'Asset Survey';

  static String surveySubtitle(String? serverRole) => isCplo(serverRole)
      ? 'पंचायत स्तर अधिकारी · Live GPS'
      : 'Survey new or existing assets · Live GPS';
}
