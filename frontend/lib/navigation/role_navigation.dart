import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../screens/citizen_shell.dart';
import '../screens/cplo_shell.dart';
import '../screens/gram_sachiv_shell.dart';
import '../screens/officer_shell.dart';
import '../services/auth_service.dart';

Widget dashboardForRole(UserRole role) {
  return switch (role) {
    UserRole.citizen => const CitizenShell(),
    UserRole.officer => const OfficerShell(),
    UserRole.survey || UserRole.cplo => const CploShell(),
    UserRole.gramSachiv => const GramSachivShell(),
  };
}

Widget dashboardForSession(AuthSession session) {
  if (FieldStaffCopy.isCplo(session.serverRole) ||
      session.role == UserRole.cplo ||
      session.role == UserRole.survey) {
    return const CploShell();
  }
  return dashboardForRole(session.role);
}
