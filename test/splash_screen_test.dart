import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/splash_screen.dart';

void main() {
  testWidgets(
      'SplashScreen displays animated app icon, title, loading status, and bnbkio',
      (WidgetTester tester) async {
    bool splashCompleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          onSplashComplete: () {
            splashCompleted = true;
          },
        ),
      ),
    );

    // Initial render
    await tester.pump();

    // Verify title and branding elements are present
    expect(find.text('PixelTools'), findsOneWidget);
    expect(find.text('Convert · Edit · Create'), findsOneWidget);
    expect(find.text('bnbkio'), findsOneWidget);

    // Verify loading status is displayed
    expect(find.text('Initializing...'), findsOneWidget);

    // Fast-forward animation partially
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Loading tools...'), findsOneWidget);
    expect(find.text('bnbkio'), findsOneWidget);

    // Fast-forward to completion
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 500));

    // Callback should be fired
    expect(splashCompleted, isTrue);
  });
}
