// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pixeltools/core/app/pixeltools_app.dart';
import 'package:pixeltools/core/settings/app_settings.dart';

void main() {
  testWidgets('Home renders tool grid', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(
              const AppSettingsState(
                savePath: '/test/path',
                hasCompletedOnboarding: true,
              ),
            ),
          ),
        ],
        child: const PixelToolsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PixelTools'), findsOneWidget);
    expect(find.text('Work Smarter'), findsOneWidget);
    expect(find.text('Resize'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('First time app launch shows in-app feature highlight spotlight',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(
              const AppSettingsState(
                savePath: '/test/path',
                hasCompletedOnboarding: false,
              ),
            ),
          ),
        ],
        child: const PixelToolsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Skip Tour'), findsOneWidget);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
  });
}

