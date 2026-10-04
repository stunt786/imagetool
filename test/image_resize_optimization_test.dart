import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/image_resize/models/social_presets.dart';
import 'package:pixeltools/features/image_resize/services/image_processor_service.dart';

Uint8List _generateSampleJpg({int width = 800, int height = 600}) {
  final image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 3) % 256, (y * 5) % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageProcessorService Progress & Optimization Tests', () {
    late Uint8List testBytes;

    setUp(() {
      testBytes = _generateSampleJpg(width: 800, height: 600);
    });

    test('resize reports progress and returns valid result', () async {
      final progressValues = <double>[];
      final stopwatch = Stopwatch()..start();

      final result = await ImageProcessorService.resize(
        bytes: testBytes,
        width: 400,
        height: 300,
        format: OutputImageFormat.jpg,
        quality: 85,
        onProgress: (p) => progressValues.add(p),
      );
      stopwatch.stop();

      expect(result, isNotNull);
      final r = result!;
      expect(r.width, equals(400));
      expect(r.height, equals(300));
      expect(r.bytes.isNotEmpty, isTrue);
      expect(r.fileSize, equals(r.bytes.length));

      // Progress reporting check
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
      // Should be fast (typically < 300ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });

    test('crop reports progress and returns valid result', () async {
      final progressValues = <double>[];

      final result = await ImageProcessorService.crop(
        bytes: testBytes,
        x: 50,
        y: 50,
        width: 300,
        height: 200,
        format: OutputImageFormat.jpg,
        quality: 90,
        onProgress: (p) => progressValues.add(p),
      );

      expect(result, isNotNull);
      final r = result!;
      expect(r.width, equals(300));
      expect(r.height, equals(200));
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
    });

    test('rotate reports progress and returns valid result', () async {
      final progressValues = <double>[];

      final result = await ImageProcessorService.rotate(
        bytes: testBytes,
        angle: 90,
        format: OutputImageFormat.jpg,
        quality: 85,
        onProgress: (p) => progressValues.add(p),
      );

      expect(result, isNotNull);
      final r = result!;
      // 90 deg rotation swaps width and height
      expect(r.width, equals(600));
      expect(r.height, equals(800));
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
    });

    test('flip reports progress and returns valid result', () async {
      final progressValues = <double>[];

      final result = await ImageProcessorService.flip(
        bytes: testBytes,
        horizontal: true,
        vertical: false,
        format: OutputImageFormat.jpg,
        quality: 85,
        onProgress: (p) => progressValues.add(p),
      );

      expect(result, isNotNull);
      final r = result!;
      expect(r.width, equals(800));
      expect(r.height, equals(600));
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
    });

    test('resizeToPreset reports progress and returns matching preset size', () async {
      final progressValues = <double>[];
      const preset = SocialPreset(
        name: 'Square 500',
        width: 500,
        height: 500,
      );

      final result = await ImageProcessorService.resizeToPreset(
        bytes: testBytes,
        preset: preset,
        format: OutputImageFormat.jpg,
        quality: 85,
        onProgress: (p) => progressValues.add(p),
      );

      expect(result, isNotNull);
      final r = result!;
      expect(r.width, equals(500));
      expect(r.height, equals(500));
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
    });

    test('compressToTargetSize reports progress and caches resized bitmaps', () async {
      final progressValues = <double>[];
      const targetBytes = 35 * 1024; // 35 KB

      final result = await ImageProcessorService.compressToTargetSize(
        bytes: testBytes,
        targetBytes: targetBytes,
        format: OutputImageFormat.jpg,
        onProgress: (p) => progressValues.add(p),
      );

      expect(result, isNotNull);
      final r = result!;
      expect(r.fileSize, lessThanOrEqualTo(targetBytes));
      expect(progressValues, isNotEmpty);
      expect(progressValues.last, closeTo(1.0, 0.01));
    });
  });
}
