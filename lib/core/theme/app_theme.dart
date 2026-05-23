import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF5B4DFF),
      onPrimary: Colors.white,
      secondary: Color(0xFF00A7A0),
      onSecondary: Colors.white,
      error: Color(0xFFB42318),
      onError: Colors.white,
      surface: Color(0xFFF8F7FC),
      onSurface: Color(0xFF171B2E),
      primaryContainer: Color(0xFFE7E3FF),
      onPrimaryContainer: Color(0xFF221A72),
      secondaryContainer: Color(0xFFD5F6F2),
      onSecondaryContainer: Color(0xFF083A39),
      tertiary: Color(0xFFEC5D92),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFD9E6),
      onTertiaryContainer: Color(0xFF4C1027),
      surfaceContainerHighest: Color(0xFFEAEAF3),
      surfaceContainerHigh: Color(0xFFF0F0F8),
      surfaceContainer: Color(0xFFF5F4FB),
      surfaceContainerLow: Color(0xFFFCFBFF),
      surfaceContainerLowest: Colors.white,
      onSurfaceVariant: Color(0xFF5A6078),
      outline: Color(0xFFC5C8D8),
      outlineVariant: Color(0xFFE3E5EF),
      shadow: Color(0x1F0F172A),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFF21253A),
      onInverseSurface: Color(0xFFF5F6FB),
      inversePrimary: Color(0xFFC4BCFF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF171B2E),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: Typography.blackMountainView.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFC4BCFF),
      onPrimary: Color(0xFF2E2588),
      secondary: Color(0xFF5DD9D2),
      onSecondary: Color(0xFF003735),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF12141C),
      onSurface: Color(0xFFE6E6EE),
      primaryContainer: Color(0xFF3A309A),
      onPrimaryContainer: Color(0xFFE7E3FF),
      secondaryContainer: Color(0xFF00504D),
      onSecondaryContainer: Color(0xFFD5F6F2),
      tertiary: Color(0xFFFFB1C8),
      onTertiary: Color(0xFF5E1135),
      tertiaryContainer: Color(0xFF83284C),
      onTertiaryContainer: Color(0xFFFFD9E6),
      surfaceContainerHighest: Color(0xFF2C2E3A),
      surfaceContainerHigh: Color(0xFF22242F),
      surfaceContainer: Color(0xFF1A1C27),
      surfaceContainerLow: Color(0xFF161821),
      surfaceContainerLowest: Color(0xFF0C0E15),
      onSurfaceVariant: Color(0xFFC4C6D4),
      outline: Color(0xFF7A7D90),
      outlineVariant: Color(0xFF3B3E4E),
      shadow: Color(0x66000000),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFFE6E6EE),
      onInverseSurface: Color(0xFF12141C),
      inversePrimary: Color(0xFF5B4DFF),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
