import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/services/perspective_correction_service.dart';

Uint8List _gradient(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (x * 200 / width + y * 55 / height).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Dark frame with a white paper rectangle in the middle.
Uint8List _framedPage(int size) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 30, 30, 30, 255);
    }
  }
  for (var y = 20; y < 80; y++) {
    for (var x = 20; x < 80; x++) {
      image.setPixelRgba(x, y, 240, 240, 240, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

double _meanChannel(img.Image image) {
  var sum = 0.0;
  var count = 0;
  for (final p in image) {
    sum += p.r.toDouble();
    count++;
  }
  return sum / count;
}

double _meanAbsDiff(img.Image a, img.Image b) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      sum += (a.getPixel(x, y).r - b.getPixel(x, y).r).abs().toDouble();
      count++;
    }
  }
  return sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerspectiveCorrectionService.correct', () {
    test('returns null for undecodable input bytes', () async {
      final result = await PerspectiveCorrectionService.correct(
        bytes: Uint8List.fromList(List<int>.filled(32, 1)),
        srcPoints: const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ],
      );
      expect(result, isNull);
    });

    test('rejects a collinear (zero area) source quad', () async {
      final bytes = _gradient(80, 80);
      final result = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(10, 40),
          Offset(30, 40),
          Offset(50, 40),
          Offset(70, 40),
        ],
        targetWidth: 40,
        targetHeight: 40,
      );
      expect(result, isNull);
    });

    test('defaults the output size to the source image size', () async {
      final bytes = _gradient(80, 60);
      final result = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(0, 0),
          Offset(80, 0),
          Offset(80, 60),
          Offset(0, 60),
        ],
      );

      expect(result, isNotNull);
      expect(result!.width, 80);
      expect(result.height, 60);
      final decoded = img.decodeImage(result.bytes)!;
      expect(decoded.width, 80);
      expect(decoded.height, 60);
    });

    test('honours explicit target dimensions', () async {
      final bytes = _gradient(80, 80);
      final result = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(0, 0),
          Offset(80, 0),
          Offset(80, 80),
          Offset(0, 80),
        ],
        targetWidth: 64,
        targetHeight: 48,
      );

      expect(result, isNotNull);
      expect(result!.width, 64);
      expect(result.height, 48);
      final decoded = img.decodeImage(result.bytes)!;
      expect(decoded.width, 64);
      expect(decoded.height, 48);
    });

    test('an identity quad reproduces the source image', () async {
      final bytes = _gradient(80, 80);
      final source = img.decodeImage(bytes)!;
      final result = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(0, 0),
          Offset(80, 0),
          Offset(80, 80),
          Offset(0, 80),
        ],
        targetWidth: 80,
        targetHeight: 80,
      );

      expect(result, isNotNull);
      final out = img.decodeImage(result!.bytes)!;
      expect(out.width, 80);
      expect(out.height, 80);
      expect(_meanAbsDiff(out, source), lessThan(20),
          reason: 'identity warp + JPEG re-encode must stay close to the input');
      expect(_meanChannel(out).round(), closeTo(_meanChannel(source).round(), 20));
    });

    test('a quad around the paper drops the surrounding frame', () async {
      final bytes = _framedPage(100);

      // Only the white paper rectangle is selected.
      final cropped = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(20, 20),
          Offset(80, 20),
          Offset(80, 80),
          Offset(20, 80),
        ],
        targetWidth: 60,
        targetHeight: 60,
      );
      expect(cropped, isNotNull);
      final croppedImage = img.decodeImage(cropped!.bytes)!;
      expect(_meanChannel(croppedImage), greaterThan(200),
          reason: 'sampling inside the quad must only pick up paper pixels');

      // The full frame keeps the dark surround.
      final whole = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
        targetWidth: 100,
        targetHeight: 100,
      );
      expect(whole, isNotNull);
      final wholeImage = img.decodeImage(whole!.bytes)!;
      expect(_meanChannel(wholeImage), lessThan(160),
          reason: 'the identity quad keeps the dark frame in view');
    });

    test('a degenerate non-collinear quad never throws', () async {
      final bytes = _gradient(80, 80);
      PerspectiveCorrectionResult? result;
      Object? error;
      try {
        result = await PerspectiveCorrectionService.correct(
          bytes: bytes,
          srcPoints: const [
            Offset(40, 40),
            Offset(40, 40),
            Offset(40, 40),
            Offset(40, 40),
          ],
          targetWidth: 40,
          targetHeight: 40,
        );
      } catch (e) {
        error = e;
      }

      expect(error, isNull);
      // The service may reject the quad outright or fall back to an
      // unusable canvas, but the reported size must stay consistent.
      if (result != null) {
        expect(result!.width, 40);
        expect(result!.height, 40);
        final decoded = img.decodeImage(result!.bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 40);
        expect(decoded.height, 40);
      }
    });
  });
}
