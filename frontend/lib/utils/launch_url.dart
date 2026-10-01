import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in the device's default browser. Shows a snackbar instead of
/// throwing if nothing on the device can handle it.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}
