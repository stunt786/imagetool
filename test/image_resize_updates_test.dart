import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/image_resize/models/social_presets.dart';
import 'package:pixeltools/features/image_resize/presentation/image_resize_screen.dart';
import 'package:pixeltools/features/image_resize/services/image_processor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _generateTestJpg({int width = 1200, int height = 900}) {
  final image = img.Image(width: width, height: height);
  // Add noise/color variance so the JPEG isn't trivially compressible
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final r = (x * 7 + y * 13) % 256;
      final g = (x * 19 + y * 3) % 256;
      final b = (x * 11 + y * 17) % 256;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Smart Compression Target Size Tests', () {
    test('compressToTargetSize compresses close to target and never exceeds it', () async {
      final sourceBytes = _generateTestJpg(width: 1000, height: 800);
      expect(sourceBytes.length, greaterThan(150 * 1024));

      const targetBytes = 60 * 1024; // 60 KB
      final result = await ImageProcessorService.compressToTargetSize(
        bytes: sourceBytes,
        targetBytes: targetBytes,
        format: OutputImageFormat.jpg,
      );

      expect(result, isNotNull);
      // Strictly not higher than target
      expect(result!.fileSize, lessThanOrEqualTo(targetBytes));
      // Few KB below it, not compressed down to a tiny size
      expect(result.fileSize, greaterThan(targetBytes * 0.75));
      // Dimensions should be scaled appropriately
      expect(result.width, lessThanOrEqualTo(1000));
      expect(result.height, lessThanOrEqualTo(800));
    });

    test('compressToTargetSize with 100 KB target achieves high accuracy', () async {
      final sourceBytes = _generateTestJpg(width: 1400, height: 1000);
      expect(sourceBytes.length, greaterThan(200 * 1024));

      const targetBytes = 100 * 1024; // 100 KB
      final result = await ImageProcessorService.compressToTargetSize(
        bytes: sourceBytes,
        targetBytes: targetBytes,
        format: OutputImageFormat.jpg,
      );

      expect(result, isNotNull);
      expect(result!.fileSize, lessThanOrEqualTo(targetBytes));
      // Must be a few KB below 100 KB, not collapsed to a tiny size
      expect(result.fileSize, greaterThan(80 * 1024));
    });
  });

  group('Resize Image Screen UI & Recent Resizes Tests', () {
    testWidgets('merges Pick Images and Batch Resize into single button',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ImageResizeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // There should be a single Pick Images button
      expect(find.text('Pick Images'), findsOneWidget);
      // There should NO LONGER be a separate Batch Resize button in the empty state
      expect(find.text('Batch Resize'), findsNothing);
    });

    testWidgets('recent resizes load from and persist to SharedPreferences',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_resize_sizes_v1': ['800x600', '1920x1080', '500x500'],
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ImageResizeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final loaded = prefs.getStringList('recent_resize_sizes_v1');
      expect(loaded, isNotNull);
      expect(loaded, contains('800x600'));
      expect(loaded, contains('1920x1080'));
      expect(loaded, contains('500x500'));
    });
  });
}
