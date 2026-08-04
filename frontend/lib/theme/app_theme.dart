import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Palette ported from the basmati-survey-app sibling project's Fraunces/IBM
// Plex Sans, paddy-green/husk/soil/gold design. Existing token names (primary,
// secondary, pendingBg, brandBlue, etc.) are kept as-is and now point at these
// new values, so every existing screen re-themes automatically without
// touching each of the ~22 call-site files.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF1F4A38); // paddy
  static const secondary = Color(0xFFC68A1F); // gold
  static const background = Color(0xFFFFFDF7); // paper
  static const border = Color(0xFFDAD3BE); // line

  /// Brand color used on the splash/login screens (Mhari Panchayat branding).
  static const brandBlue = Color(0xFF1F4A38); // paddy
  static const brandBlueTint = Color(0xFFE3EAE4); // soft paddy tint

  static const greyBg = Color(0xFFF6F1E3); // husk
  static const orangeTint = Color(0xFFF3E7CE); // soft gold tint
  static const greenTint = Color(0xFFE3EAE4); // soft paddy tint
  static const blueTint = Color(0xFFE3EEFA); // soft actionBlue tint

  static const pendingBg = Color(0xFFF3E7CE); // soft gold tint
  static const pendingText = Color(0xFFC68A1F); // gold
  static const inProgressBg = Color(0xFFE3EEFA); // soft actionBlue tint
  static const inProgressText = Color(0xFF1565C0); // actionBlue (unchanged)
  static const resolvedBg = Color(0xFFE3EAE4); // soft paddy tint
  static const resolvedText = Color(0xFF1F4A38); // paddy
  static const rejectedBg = Color(0xFFF3E3DC); // soft soil tint
  static const rejectedText = Color(0xFFB5502E); // soil

  static const splashGradientEnd = Color(0xFF153228); // paddyDark

  static const mutedText = Color(0xFF5B6357); // inkSoft
  static const secondaryText = Color(0xFF5B6357); // inkSoft
  static const inputBorder = Color(0xFFDAD3BE); // line
  static const navInactive = Color(0xFFA8ADA0); // lighter inkSoft
}

class AppGradients {
  AppGradients._();

  static const header = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.secondary],
  );

  static const cta = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.secondary],
  );
}

class AppSpacing {
  AppSpacing._();

  static const screen = 16.0;
  static const gap = 10.0;
  static const gapSm = 8.0;
}

class AppRadius {
  AppRadius._();

  static const card = 14.0;
  static const button = 10.0;
  static const chip = 20.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData? _cachedLight;

  static ThemeData light() => _cachedLight ??= _buildLight();

  static ThemeData _buildLight() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.rejectedText,
      onError: Colors.white,
      surface: AppColors.background,
      onSurface: Color(0xFF22281F), // ink
    );

    final plexSans = GoogleFonts.ibmPlexSansTextTheme();
    final notoDevanagari = GoogleFonts.notoSansDevanagariTextTheme();
    const headingWeight = FontWeight.w600;

    final bodyBase = plexSans.apply(
      bodyColor: const Color(0xFF22281F),
      displayColor: const Color(0xFF22281F),
    );
    final textTheme = bodyBase.copyWith(
      displayLarge: GoogleFonts.fraunces(
        textStyle: bodyBase.displayLarge,
        fontWeight: headingWeight,
      ),
      displayMedium: GoogleFonts.fraunces(
        textStyle: bodyBase.displayMedium,
        fontWeight: headingWeight,
      ),
      displaySmall: GoogleFonts.fraunces(
        textStyle: bodyBase.displaySmall,
        fontWeight: headingWeight,
      ),
      headlineLarge: GoogleFonts.fraunces(
        textStyle: bodyBase.headlineLarge,
        fontWeight: headingWeight,
      ),
      headlineMedium: GoogleFonts.fraunces(
        textStyle: bodyBase.headlineMedium,
        fontWeight: headingWeight,
      ),
      headlineSmall: GoogleFonts.fraunces(
        textStyle: bodyBase.headlineSmall,
        fontWeight: headingWeight,
      ),
      titleLarge: GoogleFonts.fraunces(
        textStyle: bodyBase.titleLarge,
        fontWeight: headingWeight,
      ),
    );

    // Avoid GoogleFonts.* inside WidgetState resolvers (nav rebuilds often).
    const navSelected = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    );
    const navUnselected = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.navInactive,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      primaryTextTheme: notoDevanagari,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: GoogleFonts.fraunces(
          color: Colors.white,
          fontSize: 18,
          fontWeight: headingWeight,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.background,
        elevation: 1,
        shadowColor: Colors.black12,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.ibmPlexSans(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondaryText,
          side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.inputBorder,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.inputBorder,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.ibmPlexSans(color: AppColors.secondaryText),
        hintStyle: GoogleFonts.ibmPlexSans(color: AppColors.mutedText),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.orangeTint,
        labelPadding: const EdgeInsets.only(top: 4, bottom: 4),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? navSelected
              : navUnselected;
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? AppColors.primary : AppColors.navInactive,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.greyBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return const Color(0xFF5B6357);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.white,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
      ),
    );
  }
}
