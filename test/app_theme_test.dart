import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/theme/app_theme.dart';

void main() {
  group('AppTheme.light', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.light());

    test('is a Material 3 light theme', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('the scaffold reuses the scheme surface', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });

    test('the app bar is transparent, flat and 80-free', () {
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.appBarTheme.foregroundColor, const Color(0xFF171B2E));
    });

    test('cards are flat with a 28px radius and an outline', () {
      final card = theme.cardTheme;
      expect(card.elevation, 0);
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(28));
      expect(shape.side.color, theme.colorScheme.outlineVariant);
    });

    test('text uses the on-surface colour', () {
      expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
      expect(theme.textTheme.displayLarge?.color, theme.colorScheme.onSurface);
    });

    test('the palette keeps its brand colours', () {
      final scheme = theme.colorScheme;
      expect(scheme.primary, const Color(0xFF1A73E8));
      expect(scheme.secondary, const Color(0xFF00A7A0));
      expect(scheme.tertiary, const Color(0xFFEC5D92));
      expect(scheme.error, const Color(0xFFB42318));
      expect(scheme.primary, isNot(scheme.error));
      expect(scheme.onPrimary, Colors.white);
    });
  });

  group('AppTheme.dark', () {
    late ThemeData theme;

    setUp(() => theme = AppTheme.dark());

    test('is a Material 3 dark theme', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('the scaffold reuses the scheme surface', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
      expect(theme.colorScheme.surface, const Color(0xFF12141C));
    });

    test('the app bar follows the surface colour', () {
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
      expect(theme.appBarTheme.foregroundColor, theme.colorScheme.onSurface);
      expect(theme.appBarTheme.elevation, 0);
    });

    test('cards match the light theme geometry on the dark surface', () {
      final card = theme.cardTheme;
      expect(card.elevation, 0);
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(28));
      expect(shape.side.color, theme.colorScheme.outlineVariant);
    });

    test('text uses the light on-surface colour', () {
      expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
      expect(theme.textTheme.displayLarge?.color, theme.colorScheme.onSurface);
    });
  });

  group('scheme sanity', () {
    test('light and dark really differ', () {
      final light = AppTheme.light().colorScheme;
      final dark = AppTheme.dark().colorScheme;
      expect(light.primary, isNot(dark.primary));
      expect(light.surface, isNot(dark.surface));
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });

    test('every container colour is distinct from its content colour', () {
      for (final scheme in <ColorScheme>[
        AppTheme.light().colorScheme,
        AppTheme.dark().colorScheme,
      ]) {
        expect(scheme.primaryContainer, isNot(scheme.onPrimaryContainer));
        expect(scheme.secondaryContainer, isNot(scheme.onSecondaryContainer));
        expect(scheme.tertiaryContainer, isNot(scheme.onTertiaryContainer));
        expect(scheme.errorContainer, isNot(scheme.onErrorContainer));
        expect(scheme.inverseSurface, isNot(scheme.onInverseSurface));
        expect(scheme.outline, isNot(scheme.outlineVariant));
      }
    });

    test('the light surface stays lighter than its text colour', () {
      final scheme = AppTheme.light().colorScheme;
      expect(scheme.surface.computeLuminance(),
          greaterThan(scheme.onSurface.computeLuminance()));
    });

    test('the dark surface stays darker than its text colour', () {
      final scheme = AppTheme.dark().colorScheme;
      expect(scheme.surface.computeLuminance(),
          lessThan(scheme.onSurface.computeLuminance()));
    });

    test('building a light and a dark theme twice yields the same colours',
        () {
      expect(AppTheme.light().colorScheme.primary,
          AppTheme.light().colorScheme.primary);
      expect(AppTheme.dark().colorScheme.surface,
          AppTheme.dark().colorScheme.surface);
    });
  });
}
