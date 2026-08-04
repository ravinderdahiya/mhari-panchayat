enum UserRole { citizen, officer, survey }

extension UserRoleStorage on UserRole {
  String get storageValue => name;

  static UserRole? fromStorage(String? value) {
    if (value == null) return null;
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}
