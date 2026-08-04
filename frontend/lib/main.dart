import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm fonts off the critical path so first GoogleFonts.* calls
  // don't block the UI thread (common ANR cause on Android).
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.poppins(),
      GoogleFonts.poppins(fontWeight: FontWeight.w600),
      GoogleFonts.poppins(fontWeight: FontWeight.w700),
      GoogleFonts.notoSansDevanagari(),
      GoogleFonts.notoSansDevanagari(fontWeight: FontWeight.w700),
    ]).timeout(const Duration(seconds: 3));
  } catch (_) {
    // Offline / slow network — fall back to platform fonts.
  }

  runApp(const PanchayatApp());
}
