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

    // Tap Next to navigate to Step 2 (Smart Document Scanner)
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 2 OF 3'), findsOneWidget);
    expect(find.text('Smart Document Scanner'), findsOneWidget);

    // Verify card bottom is above the Camera button (never covers the menu)
    final cardFinderStep2 = find.text('Smart Document Scanner');
    final cardBottomStep2 = tester.getBottomLeft(cardFinderStep2).dy;
    final cameraTop = tester.getTopLeft(find.bySemanticsLabel('Camera')).dy;
    expect(
      cardBottomStep2,
      lessThan(cameraTop),
      reason: 'Tooltip message must be positioned above the camera button, not covering it',
    );

    // Tap Next to navigate to Step 3 (Files & PDF Hub)
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 3 OF 3'), findsOneWidget);
    expect(find.text('Files & PDF Hub'), findsOneWidget);

    // Verify card bottom is above the Files button (never covers the menu)
    final cardFinderStep3 = find.text('Files & PDF Hub');
    final cardBottomStep3 = tester.getBottomLeft(cardFinderStep3).dy;
    final filesTop = tester.getTopLeft(find.bySemanticsLabel('Files')).dy;
    expect(
      cardBottomStep3,
      lessThan(filesTop),
      reason: 'Tooltip message must be positioned above the files button, not covering it',
    );

    // Tap Got it! to finish tour
    await tester.tap(find.text('Got it!'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 3 OF 3'), findsNothing);
  });
}

