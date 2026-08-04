import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../screens/asset_survey_screen.dart';
import '../screens/citizen_shell.dart';
import '../screens/officer_shell.dart';

Widget dashboardForRole(UserRole role) {
  return switch (role) {
    UserRole.citizen => const CitizenShell(),
    UserRole.officer => const OfficerShell(),
    UserRole.survey => const AssetSurveyScreen(),
  };
}
