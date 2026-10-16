import 'package:flutter/material.dart';

import '../services/app_version_service.dart';

/// Shows the installed app version (e.g. "Version 1.0.1 (2)"). [format] turns
/// the version into the label; nothing is shown until it's known.
class AppVersionText extends StatefulWidget {
  const AppVersionText({
    super.key,
    required this.format,
    this.style,
    this.textAlign,
  });

  final String Function(String version) format;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<AppVersionText> createState() => _AppVersionTextState();
}

class _AppVersionTextState extends State<AppVersionText> {
  late final Future<String> _version = AppVersionService.displayVersion();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) {
        final version = snapshot.data ?? '';
        if (version.isEmpty) return const SizedBox.shrink();
        return Text(
          widget.format(version),
          style: widget.style,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}
