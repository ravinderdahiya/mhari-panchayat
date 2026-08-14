import 'package:flutter/material.dart';

/// Replaces the whole app instead of just showing a dialog over it - the
/// app is never allowed to run while Android Developer Options is on, so
/// this is the entire widget tree main() hands to runApp() in that case.
class DeveloperModeBlockedScreen extends StatelessWidget {
  const DeveloperModeBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 72,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Developer Mode Enabled',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'For security reasons, Mhari Panchayat cannot run while '
                    'Developer Options is turned on.\n\n'
                    'Please go to Settings > System > Developer Options, '
                    'turn it off, then reopen the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
