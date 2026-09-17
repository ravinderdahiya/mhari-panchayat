import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_controller.dart';

// Palette ported from the basmati-survey-app sibling project's Fraunces/IBM
// Plex Sans, paddy-green/husk/soil/gold design. Existing token names (primary,
// secondary, pendingBg, brandBlue, etc.) are kept as-is and now point at these
// new values, so every existing screen re-themes automatically without
// touching each of the ~22 call-site files.
//
// Brand colors (primary/secondary/brandBlue/splashGradientEnd) stay fixed
// across light and dark - only surface/neutral/status tokens flip, via
// [_LightPalette]/[_DarkPalette] below. `AppColors.*` reads whichever one
// matches [ThemeController]'s current value.
class _LightPalette {
  _LightPalette._();

  static const background = Color(0xFFFFFDF7); // paper
  static const border = Color(0xFFDAD3BE); // line
  static const greyBg = Color(0xFFF6F1E3); // husk
  static const orangeTint = Color(0xFFF3E7CE); // soft gold tint
  static const greenTint = Color(0xFFE3EAE4); // soft paddy tint
  static const blueTint = Color(0xFFE3EEFA); // soft actionBlue tint
  static const brandBlueTint = Color(0xFFE3EAE4); // soft paddy tint

  static const pendingBg = Color(0xFFF3E7CE);
  static const pendingText = Color(0xFFC68A16);
  static const inProgressBg = Color(0xFFE3EEFA);
  static const inProgressText = Color(0xFF1565C0);
  static const resolvedBg = Color(0xFFE3EAE4);
  static const resolvedText = Color(0xFF1F4A38);
  static const rejectedBg = Color(0xFFF3E3DC);
  static const rejectedText = Color(0xFFB5502E);

  static const mutedText = Color(0xFF5B6357); // inkSoft
  static const navInactive = Color(0xFFA8ADA0);
  static const ink = Color(0xFF22281F);
}

class _DarkPalette {
  _DarkPalette._();

  static const background = Color(0xFF151915);
  static const border = Color(0xFF333A2F);
  static const greyBg = Color(0xFF1E241E);
  static const orangeTint = Color(0xFF3A2F17);
  static const greenTint = Color(0xFF1E2A22);
  static const blueTint = Color(0xFF1A2733);
  static const brandBlueTint = Color(0xFF1E2A22);

  static const pendingBg = Color(0xFF3A2F17);
  static const pendingText = Color(0xFFE0AE55);
  static const inProgressBg = Color(0xFF1A2733);
  static const inProgressText = Color(0xFF6FA8E0);
  static const resolvedBg = Color(0xFF1E2A22);
  static const resolvedText = Color(0xFF6FBE9A);
  static const rejectedBg = Color(0xFF3A241D);
  static const rejectedText = Color(0xFFE08A66);

  static const mutedText = Color(0xFFA9B0A3);
  static const navInactive = Color(0xFF7C8377);
  static const ink = Color(0xFFEDEFEA);
}

class AppColors {
  AppColors._();

  static bool get _isDark => ThemeController.instance.value;

  // Brand colors - unchanged across light/dark.
  static const primary = Color(0xFF1F4A38); // paddy
  static const secondary = Color(0xFFC68A1F); // gold
  static const brandBlue = Color(0xFF1F4A38); // paddy
  static const splashGradientEnd = Color(0xFF153228); // paddyDark

  // Surface/neutral/status tokens - flip with the current theme.
  static Color get background =>
      _isDark ? _DarkPalette.background : _LightPalette.background;
  static Color get border => _isDark ? _DarkPalette.border : _LightPalette.border;
  static Color get greyBg => _isDark ? _DarkPalette.greyBg : _LightPalette.greyBg;
  static Color get orangeTint =>
      _isDark ? _DarkPalette.orangeTint : _LightPalette.orangeTint;
  static Color get greenTint =>
      _isDark ? _DarkPalette.greenTint : _LightPalette.greenTint;
  static Color get blueTint => _isDark ? _DarkPalette.blueTint : _LightPalette.blueTint;
  static Color get brandBlueTint =>
      _isDark ? _DarkPalette.brandBlueTint : _LightPalette.brandBlueTint;

  static Color get pendingBg => _isDark ? _DarkPalette.pendingBg : _LightPalette.pendingBg;
  static Color get pendingText =>
      _isDark ? _DarkPalette.pendingText : _LightPalette.pendingText;
  static Color get inProgressBg =>
      _isDark ? _DarkPalette.inProgressBg : _LightPalette.inProgressBg;
  static Color get inProgressText =>
      _isDark ? _DarkPalette.inProgressText : _LightPalette.inProgressText;
  static Color get resolvedBg =>
      _isDark ? _DarkPalette.resolvedBg : _LightPalette.resolvedBg;
  static Color get resolvedText =>
      _isDark ? _DarkPalette.resolvedText : _LightPalette.resolvedText;
  static Color get rejectedBg =>
      _isDark ? _DarkPalette.rejectedBg : _LightPalette.rejectedBg;
  static Color get rejectedText =>
      _isDark ? _DarkPalette.rejectedText : _LightPalette.rejectedText;

  static Color get mutedText => _isDark ? _DarkPalette.mutedText : _LightPalette.mutedText;
  static Color get secondaryText =>
      _isDark ? _DarkPalette.mutedText : _LightPalette.mutedText;
  static Color get ink => _isDark ? _DarkPalette.ink : _LightPalette.ink;
  static Color get inputBorder => _isDark ? _DarkPalette.border : _LightPalette.border;
  static Color get navInactive =>
      _isDark ? _DarkPalette.navInactive : _LightPalette.navInactive;
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
  static ThemeData? _cachedDark;

  static ThemeData light() => _cachedLight ??= _build(
        brightness: Brightness.light,
        background: _LightPalette.background,
        border: _LightPalette.border,
        ink: _LightPalette.ink,
        muted: _LightPalette.mutedText,
        navInactive: _LightPalette.navInactive,
        orangeTint: _LightPalette.orangeTint,
        error: _LightPalette.rejectedText,
      );

  static ThemeData dark() => _cachedDark ??= _build(
        brightness: Brightness.dark,
        background: _DarkPalette.background,
        border: _DarkPalette.border,
        ink: _DarkPalette.ink,
        muted: _DarkPalette.mutedText,
        navInactive: _DarkPalette.navInactive,
        orangeTint: _DarkPalette.orangeTint,
        error: _DarkPalette.rejectedText,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color border,
    required Color ink,
    required Color muted,
    required Color navInactive,
    required Color orangeTint,
    required Color error,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: background,
      onSurface: ink,
    );

    final plexSans = GoogleFonts.ibmPlexSansTextTheme();
    final notoDevanagari = GoogleFonts.notoSansDevanagariTextTheme();
    const headingWeight = FontWeight.w600;

    final bodyBase = plexSans.apply(bodyColor: ink, displayColor: ink);
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
    final navSelected = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
    );
    final navUnselected = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: navInactive,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
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
        color: background,
        elevation: 1,
        shadowColor: Colors.black12,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 0.5),
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
          foregroundColor: muted,
          side: BorderSide(color: border, width: 1.5),
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
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.ibmPlexSans(color: muted),
        hintStyle: GoogleFonts.ibmPlexSans(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: background,
        indicatorColor: orangeTint,
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
            color: selected ? AppColors.primary : navInactive,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return background == _LightPalette.background
                ? _LightPalette.greyBg
                : _DarkPalette.greyBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return muted;
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
      dividerTheme: DividerThemeData(color: border, thickness: 0.5),
    );
  }
}
