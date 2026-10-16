import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_version_service.dart';
import '../theme/app_theme.dart';

/// "Update available" prompt. A forced update can't be dismissed (no Later
/// button, back is swallowed) and stays open after tapping Update Now, so the
/// app is unusable until the new build is installed. Returns once an optional
/// update is dismissed with "Later".
Future<void> showUpdateDialog(BuildContext context, AppVersionCheck check) {
  final force = check.status == UpdateStatus.force;

  return showDialog<void>(
    context: context,
    barrierDismissible: !force,
    builder: (dialogContext) => PopScope(
      canPop: !force,
      child: AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(
          force ? 'Update Required' : 'Update Available',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          check.message ?? 'A new version of the app is available. Please update.',
          style: GoogleFonts.poppins(fontSize: 14, height: 1.4),
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Later', style: GoogleFonts.poppins()),
            ),
          FilledButton(
            onPressed: () => AppVersionService.openStore(check.storeUrl),
            child: Text(
              'Update Now',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
