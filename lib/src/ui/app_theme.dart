import 'package:flutter/material.dart';

import 'branding/sb_brand.dart';

class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: SbBrand.electricBlue,
      secondary: SbBrand.purple,
      surface: SbBrand.panel,
      surfaceContainerHighest: SbBrand.panelBlue,
      error: SbBrand.liveError,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: SbBrand.textPrimary,
      onSurfaceVariant: SbBrand.textMuted,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SbBrand.black,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          color: SbBrand.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -2.4,
        ),
        displayMedium: const TextStyle(
          color: SbBrand.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.8,
        ),
        headlineLarge: const TextStyle(
          color: SbBrand.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
        ),
        headlineMedium: const TextStyle(
          color: SbBrand.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleLarge: const TextStyle(
          color: SbBrand.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: const TextStyle(
          color: SbBrand.textPrimary,
          height: 1.4,
        ),
        bodyMedium: const TextStyle(
          color: SbBrand.textPrimary,
          height: 1.35,
        ),
        bodySmall: const TextStyle(
          color: SbBrand.textMuted,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: SbBrand.panel.withValues(alpha: 0.92),
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: SbBrand.electricBlue.withValues(alpha: 0.22),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SbBrand.elevated.withValues(alpha: 0.96),
        labelStyle: const TextStyle(color: SbBrand.textMuted),
        hintStyle: TextStyle(
          color: SbBrand.textMuted.withValues(alpha: 0.76),
        ),
        prefixIconColor: SbBrand.textMuted,
        suffixIconColor: SbBrand.textMuted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: SbBrand.brightBlue.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: SbBrand.electricBlue,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SbBrand.liveError),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor:
              const WidgetStatePropertyAll(SbBrand.electricBlue),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStatePropertyAll(
            SbBrand.brightBlue.withValues(alpha: 0.18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(SbBrand.textPrimary),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: SbBrand.electricBlue.withValues(alpha: 0.40),
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: SbBrand.electricBlue.withValues(alpha: 0.14),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: SbBrand.elevated,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SbBrand.black,
        foregroundColor: SbBrand.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: SbBrand.elevated.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: SbBrand.electricBlue.withValues(alpha: 0.20),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SbBrand.elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: SbBrand.electricBlue.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}
