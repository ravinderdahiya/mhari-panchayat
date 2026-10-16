import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_version_service.dart';
import '../theme/app_theme.dart';

/// "About Mhari Panchayat" dialog: name, installed version and department.
/// Used instead of Flutter's showAboutDialog, which always adds a
/// "View licenses" button.
Future<void> showAboutAppDialog(BuildContext context) async {
  final version = await AppVersionService.displayVersion();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(
        'Mhari Panchayat',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (version.isNotEmpty)
            Text('Version $version', style: GoogleFonts.poppins(fontSize: 14)),
          const SizedBox(height: 16),
          Text(
            'Development and Panchayats Department, Government of Haryana',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('Close', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
