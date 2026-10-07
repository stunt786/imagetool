import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/app/orientation_hint.dart';
import 'package:pixeltools/core/app/system_ui.dart';

void main() {
  test('every orientation is allowed so portrait stays the default', () {
    expect(AppSystemUi.allOrientations, containsAll(DeviceOrientation.values));
  });

  test('overlay style keeps status and navigation icons readable', () {
    final light = AppSystemUi.overlayStyle(Brightness.light);
    final dark = AppSystemUi.overlayStyle(Brightness.dark);

    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(light.statusBarColor, const Color(0x00000000));
    expect(light.systemNavigationBarColor, const Color(0x00000000));
  });

  group('OrientationHint', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: AppSystemUi.appBuilder(null),
          home: const Scaffold(body: Center(child: Text('ScreenBody'))),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('stays silent while portrait', (tester) async {
      await pumpApp(tester);

      expect(find.text(OrientationHint.message), findsNothing);
    });

    testWidgets('stays silent when it already starts in landscape',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: AppSystemUi.appBuilder(null),
          home: const Scaffold(body: Center(child: Text('ScreenBody'))),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('suggests portrait once when rotated to landscape',
        (tester) async {
      await pumpApp(tester);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text(OrientationHint.message), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    /// Advances time until no `SnackBar` is on screen (entrance and exit
    /// animations included).
    Future<void> pumpUntilSnackBarGone(WidgetTester tester) async {
      for (var i = 0; i < 80 && find.byType(SnackBar).evaluate().isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('does not repeat while the user stays in landscape',
        (tester) async {
      await pumpApp(tester);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      expect(find.text(OrientationHint.message), findsOneWidget);

      await pumpUntilSnackBarGone(tester);
      expect(find.byType(SnackBar), findsNothing);

      // Unrelated rebuilds while still landscape must not re-fire the hint.
      tester.view.physicalSize = const Size(900, 410);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(OrientationHint.message), findsNothing);
    });

    testWidgets('arms the hint again after returning to portrait',
        (tester) async {
      await pumpApp(tester);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      expect(find.text(OrientationHint.message), findsOneWidget);

      await pumpUntilSnackBarGone(tester);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump();
      await pumpUntilSnackBarGone(tester);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();

      expect(find.text(OrientationHint.message), findsOneWidget);
    });
  });
}
