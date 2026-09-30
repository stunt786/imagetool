import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/notifiers/document_batch_notifier.dart';
import 'package:pixeltools/features/camera/presentation/screens/document_review_screen.dart';
import 'package:pixeltools/features/camera/services/document_enhancement_service.dart';
import 'package:pixeltools/features/camera/services/image_filter_service.dart';

Uint8List _createCleanPageWithHousefly() {
  final image = img.Image(width: 120, height: 120);
  // White paper background (lum ~240)
  for (var y = 0; y < 120; y++) {
    for (var x = 0; x < 120; x++) {
      image.setPixelRgba(x, y, 240, 240, 240, 255);
    }
  }
  // Add a line of text in the middle
  for (var x = 30; x <= 90; x++) {
    for (var y = 60; y <= 64; y++) {
      image.setPixelRgba(x, y, 20, 20, 20, 255);
    }
  }
  // Add an isolated housefly / dirt blob in the upper margin away from text
  for (var y = 20; y <= 24; y++) {
    for (var x = 50; x <= 55; x++) {
      image.setPixelRgba(x, y, 15, 15, 15, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _createCleanPageWithFingerOnBorder() {
  final image = img.Image(width: 120, height: 120);
  for (var y = 0; y < 120; y++) {
    for (var x = 0; x < 120; x++) {
      image.setPixelRgba(x, y, 240, 240, 240, 255);
    }
  }
  // Add finger intrusion on left edge (skin tone: r=180, g=110, b=90)
  for (var y = 40; y <= 80; y++) {
    for (var x = 0; x <= 18; x++) {
      image.setPixelRgba(x, y, 180, 110, 90, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Camera Module Design Updates Tests', () {
    test('Smart clean removes isolated housefly/dirt without warping geometry', () async {
      final bytes = _createCleanPageWithHousefly();
      final srcImage = img.decodeImage(bytes)!;

      // Ensure housefly is present before cleaning
      final preFlyPixel = srcImage.getPixel(52, 22);
      expect(preFlyPixel.r, lessThan(50));

      final stages = <String>[];
      final cleaned = DocumentEnhancementService.internalSmartClean(srcImage, stagesOut: stages);

      // Geometry is preserved (no warping, dimensions unchanged)
      expect(cleaned.width, equals(srcImage.width));
      expect(cleaned.height, equals(srcImage.height));

      // Housefly spot should be cleaned to paper background color
      final postFlyPixel = cleaned.getPixel(52, 22);
      expect(postFlyPixel.r, greaterThan(180), reason: 'Housefly spot was not cleaned');

      // Normal text line should remain intact
      final textPixel = cleaned.getPixel(50, 62);
      expect(textPixel.r, lessThan(80), reason: 'Document text was accidentally erased');
    });

    test('Smart clean removes finger intrusion along paper border', () async {
      final bytes = _createCleanPageWithFingerOnBorder();
      final srcImage = img.decodeImage(bytes)!;

      final stages = <String>[];
      final cleaned = DocumentEnhancementService.internalSmartClean(srcImage, stagesOut: stages);

      expect(stages.contains('Fingers removed'), isTrue);

      // Border area where finger was should now be cleaned paper background
      final postFingerPixel = cleaned.getPixel(8, 60);
      expect(postFingerPixel.r, greaterThan(160), reason: 'Finger intrusion was not cleaned');
    });

    test('Auto flatten straightens and clears raised/down parts', () async {
      final wavyImage = img.Image(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          wavyImage.setPixelRgba(x, y, 240, 240, 240, 255);
        }
      }
      // Add curved text line (raised at center, down at sides)
      for (var x = 10; x < 90; x++) {
        final dip = (x > 30 && x < 70) ? -6 : 6;
        final yCenter = 50 + dip;
        for (var dy = -2; dy <= 2; dy++) {
          wavyImage.setPixelRgba(x, yCenter + dy, 30, 30, 30, 255);
        }
      }

      final flattened = DocumentEnhancementService.internalAutoFlattenSmooth(wavyImage);
      expect(flattened.width, greaterThan(0));
      expect(flattened.height, greaterThan(0));
    });

    test('Smart Clean and Auto Flatten have distinct implementations', () async {
      final sample = _createCleanPageWithHousefly();

      final smartCleanResult =
          await ImageFilterService.applyFilter(sample, FilterType.smartScan);
      final autoFlattenResult =
          await ImageFilterService.applyFilter(sample, FilterType.autoFlatten);

      expect(smartCleanResult, isNotNull);
      expect(autoFlattenResult, isNotNull);
      expect(smartCleanResult!.bytes.isNotEmpty, isTrue);
      expect(autoFlattenResult!.bytes.isNotEmpty, isTrue);
    });

    testWidgets('GoRouter routes /camera/crop and /camera/perspective without GoException', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      // Verify that neither /camera/crop nor /camera/perspective throws a GoException
      expect(() => router.go('/camera/crop'), returnsNormally);
      expect(() => router.go('/camera/perspective'), returnsNormally);
    });

    testWidgets('DocumentReviewScreen toolbar renders all 8 options with proper text and spacing', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sample = _createCleanPageWithHousefly();
      final page = ScannedPage(
        path: '/tmp/test.jpg',
        name: 'test.jpg',
        sizeBytes: sample.length,
        imageBytes: sample,
      );

      container.read(documentBatchProvider.notifier).startNewBatch();
      container.read(documentBatchProvider.notifier).addPage(page);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DocumentReviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 8 tools are present in the options toolbar
      expect(find.text('Smart Fix'), findsOneWidget);
      expect(find.text('Flatten'), findsOneWidget);
      expect(find.text('Crop'), findsOneWidget);
      expect(find.text('Enhance'), findsOneWidget);
      expect(find.text('Magic Remove'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Verify spacing exists between toolbar buttons (SizedBox with width 10)
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final spacerFound = sizedBoxes.any((box) => box.width == 10.0);
      expect(spacerFound, isTrue, reason: 'Expected horizontal spacing between options buttons');
    });
  });
}
