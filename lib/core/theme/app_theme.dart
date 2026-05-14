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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    );
  }
}
