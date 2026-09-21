import 'package:flutter/material.dart';

import 'branding/sb_brand.dart';

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SbBrand.electricBlue,
      brightness: Brightness.dark,
      surface: SbBrand.panel,
      error: SbBrand.liveError,
    ).copyWith(
      primary: SbBrand.electricBlue,
      secondary: SbBrand.purple,
      surface: SbBrand.panel,
      onSurface: SbBrand.textPrimary,
      onSurfaceVariant: SbBrand.textMuted,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SbBrand.black,
      colorScheme: scheme,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.6,
          color: SbBrand.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
          color: SbBrand.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
          color: SbBrand.textPrimary,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
          color: SbBrand.textPrimary,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: SbBrand.textPrimary,
        ),
        bodyLarge: TextStyle(
          color: SbBrand.textPrimary,
          height: 1.42,
        ),
        bodyMedium: TextStyle(
          color: SbBrand.textPrimary,
          height: 1.38,
        ),
        bodySmall: TextStyle(
          color: SbBrand.textMuted,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: SbBrand.panel,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: Colors.white.withValues(alpha: .08),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SbBrand.elevated,
        hintStyle: const TextStyle(color: SbBrand.textMuted),
        labelStyle: const TextStyle(color: SbBrand.textMuted),
        prefixIconColor: SbBrand.textMuted,
        suffixIconColor: SbBrand.textMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: .1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: .11),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: SbBrand.electricBlue,
            width: 1.5,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SbBrand.electricBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SbBrand.textPrimary,
          side: BorderSide(color: Colors.white.withValues(alpha: .14)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SbBrand.elevated,
        selectedColor: SbBrand.panelBlue,
        side: BorderSide(color: Colors.white.withValues(alpha: .10)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        labelStyle: const TextStyle(color: SbBrand.textPrimary),
      ),
      dividerColor: Colors.white.withValues(alpha: .08),
      appBarTheme: const AppBarTheme(
        backgroundColor: SbBrand.black,
        foregroundColor: SbBrand.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SbBrand.electricBlue,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: SbBrand.panelBlue,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        textStyle: const TextStyle(color: SbBrand.textPrimary),
      ),
    );
  }
}
