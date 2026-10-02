import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixeltools/core/constants/app_strings.dart';
import 'package:pixeltools/core/services/app_review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppReviewService.instance.enableInTest = true;
  });

  tearDown(() {
    AppReviewService.instance.enableInTest = false;
  });

  group('AppReviewService Unit Tests', () {
    test('Initial rating state is unrated', () async {
      final service = AppReviewService.instance;
      expect(await service.hasRated(), isFalse);
    });

    test('markAsRated persists and prevents future rating prompts', () async {
      final service = AppReviewService.instance;
      await service.markAsRated();
      expect(await service.hasRated(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_review_has_rated'), isTrue);
    });

    test('Play Store URL contains correct package name', () {
      expect(AppStrings.playStoreUrl, contains('com.bnbkio.pixeltools'));
    });
  });

  group('AppReviewService Dialog and Frequency Tests', () {
    testWidgets('Prompts on 1st operation completed when unrated', (tester) async {
      final service = AppReviewService.instance;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => service.notifyOperationCompleted(context),
                  child: const Text('Do Operation'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Do Operation'));
      await tester.pump(const Duration(milliseconds: 700));

      // Rating dialog should appear
      expect(find.text('Enjoying PixelTools?'), findsOneWidget);
      expect(find.text('Rate Now'), findsOneWidget);
      expect(find.text('Remind Later'), findsOneWidget);

      // Tap Remind Later
      await tester.tap(find.text('Remind Later'));
      await tester.pumpAndSettle();

      expect(find.text('Enjoying PixelTools?'), findsNothing);
      expect(await service.hasRated(), isFalse);
    });

    testWidgets('Does not prompt if user already rated', (tester) async {
      final service = AppReviewService.instance;
      await service.markAsRated();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => service.notifyOperationCompleted(context),
                  child: const Text('Do Operation'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Do Operation'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Enjoying PixelTools?'), findsNothing);
    });

    testWidgets('Does not prompt within 48-hour interval after previous prompt', (tester) async {
      final service = AppReviewService.instance;
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      // Set last prompt to 24 hours ago (less than 48 hours)
      await prefs.setInt('app_review_last_prompt_ms', now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch);
      await prefs.setInt('app_review_operation_count', 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => service.notifyOperationCompleted(context),
                  child: const Text('Do Operation'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Do Operation'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Enjoying PixelTools?'), findsNothing);
    });

    testWidgets('Prompts after 48-hour interval has elapsed since last prompt', (tester) async {
      final service = AppReviewService.instance;
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      // Set last prompt to 49 hours ago (more than 48 hours)
      await prefs.setInt('app_review_last_prompt_ms', now.subtract(const Duration(hours: 49)).millisecondsSinceEpoch);
      await prefs.setInt('app_review_operation_count', 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => service.notifyOperationCompleted(context),
                  child: const Text('Do Operation'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Do Operation'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Enjoying PixelTools?'), findsOneWidget);

      // Tap 'Rate Now' marks as rated
      await tester.tap(find.text('Rate Now'));
      await tester.pumpAndSettle();

      expect(await service.hasRated(), isTrue);
    });
  });
}
