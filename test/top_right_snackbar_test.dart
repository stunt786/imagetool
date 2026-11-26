import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/app/system_ui.dart';
import 'package:pixeltools/core/ui/app_snackbars.dart';

void main() {
  testWidgets('operation messages are shown in the top-right corner',
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        builder: AppSystemUi.appBuilder(null),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    messengerKey.currentState!.showTopSnackBar(
      const SnackBar(
        content: Text('Saved successfully'),
        duration: Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Saved successfully'), findsOneWidget);

    final Size screen = tester.getSize(find.byType(MaterialApp));
    final Rect message = tester.getRect(find.byType(SnackBar));

    // Top-right corner: clear of the status bar but near the top, and pushed
    // against the right edge instead of spanning the full width.
    expect(message.top, lessThan(screen.height * 0.15));
    expect(message.right, greaterThan(screen.width - 40));
    expect(message.width, lessThan(screen.width));

    // It dismisses itself after the configured duration.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('replacing a message removes the previous one',
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        builder: AppSystemUi.appBuilder(null),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    messengerKey.currentState!.showTopSnackBar(
      const SnackBar(content: Text('First message')),
    );
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsOneWidget);

    messengerKey.currentState!
      ..clearTopSnackBars()
      ..showTopSnackBar(const SnackBar(content: Text('Second message')));
    await tester.pumpAndSettle();

    expect(find.text('First message'), findsNothing);
    expect(find.text('Second message'), findsOneWidget);
  });

  testWidgets('snackbar actions dismiss the message', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    var actionPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        builder: AppSystemUi.appBuilder(null),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    messengerKey.currentState!.showTopSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => actionPressed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copied to clipboard'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(actionPressed, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('falls back to the bottom snackbar without the app overlay',
      (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    messengerKey.currentState!.showTopSnackBar(
      const SnackBar(content: Text('Plain message')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    final Size screen = tester.getSize(find.byType(MaterialApp));
    final Rect message = tester.getRect(find.byType(SnackBar));
    expect(message.bottom, greaterThan(screen.height * 0.9));
  });
}
