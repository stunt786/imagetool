import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/services/platform_image_encoder.dart';

Uint8List _png({int width = 64, int height = 48, int gray = 120}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7 + y * 3) & 0xFF, (y * 5) & 0xFF, gray);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

bool _isWebP(Uint8List bytes) =>
    bytes.length > 12 &&
    bytes[0] == 0x52 && // R
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x46 && // F
    bytes[8] == 0x57 && // W
    bytes[9] == 0x45 && // E
    bytes[10] == 0x42 && // B
    bytes[11] == 0x50; // P

void main() {
  group('PlatformImageEncoder.supportsWebP', () {
    test('is available on every platform', () {
      expect(PlatformImageEncoder.supportsWebP, isTrue);
    });
  });

  group('PlatformImageEncoder.encodeWebP', () {
    test('rejects empty input instead of throwing', () async {
      expect(await PlatformImageEncoder.encodeWebP(Uint8List(0)), isNull);
    });

    test('returns null for data that is not an image', () async {
      final junk = Uint8List.fromList(List<int>.filled(64, 7));
      expect(await PlatformImageEncoder.encodeWebP(junk), isNull);
    });

    test('encodes a PNG to a real WebP container', () async {
      final result = await PlatformImageEncoder.encodeWebP(_png());

      expect(result, isNotNull);
      expect(result, isNotEmpty);
      expect(_isWebP(result!), isTrue);

      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
    });

    test('encodes JPEG input too', () async {
      final image = img.Image(width: 32, height: 32);
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 80));

      final result = await PlatformImageEncoder.encodeWebP(jpeg);
      expect(result, isNotNull);
      expect(_isWebP(result!), isTrue);
    });

    test('scales the output to maxWidth/maxHeight', () async {
      final result = await PlatformImageEncoder.encodeWebP(
        _png(width: 400, height: 300),
        maxWidth: 100,
        maxHeight: 100,
      );

      expect(result, isNotNull);
      final decoded = img.decodeImage(result!);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(100));
      expect(decoded.height, lessThanOrEqualTo(100));
      expect(decoded.width, greaterThan(0));
    });

    test('quality 100 encodes losslessly while lower quality does not',
        () async {
      final source = _png(width: 200, height: 200);
      final lossy = await PlatformImageEncoder.encodeWebP(
        source,
        quality: 30,
      );
      final lossless = await PlatformImageEncoder.encodeWebP(
        source,
        quality: 100,
      );

      expect(lossy, isNotNull);
      expect(lossless, isNotNull);
      expect(_isWebP(lossy!), isTrue);
      expect(_isWebP(lossless!), isTrue);
      expect(lossy.length, isNot(lossless.length));

      final original = img.decodeImage(source)!;
      final restored = img.decodeImage(lossless)!;
      expect(restored.width, original.width);
      expect(restored.height, original.height);

      var identicalPixels = true;
      for (var y = 0; y < original.height && identicalPixels; y++) {
        for (var x = 0; x < original.width; x++) {
          final a = original.getPixel(x, y);
          final b = restored.getPixel(x, y);
          if (a.r != b.r || a.g != b.g || a.b != b.b) {
            identicalPixels = false;
            break;
          }
        }
      }
      expect(identicalPixels, isTrue,
          reason: 'a lossless WebP must round-trip pixel for pixel');
    });

    test('an out-of-range quality is clamped instead of throwing', () async {
      final low = await PlatformImageEncoder.encodeWebP(
        _png(width: 40, height: 40),
        quality: 0,
      );
      final high = await PlatformImageEncoder.encodeWebP(
        _png(width: 40, height: 40),
        quality: 999,
      );
      expect(low, isNotNull);
      expect(high, isNotNull);
      expect(_isWebP(low!), isTrue);
      expect(_isWebP(high!), isTrue);
    });

    test('non-PNG/JPEG input is re-encoded through PNG first', () async {
      // GIF: neither a JPEG nor a PNG signature, so the Android branch has to
      // decode it before compressing. Off Android the pure Dart path decodes
      // it directly; both must yield WebP.
      final image = img.Image(width: 24, height: 24);
      final gif = Uint8List.fromList(img.encodeGif(image));

      final result = await PlatformImageEncoder.encodeWebP(gif, quality: 80);
      expect(result, isNotNull);
      expect(_isWebP(result!), isTrue);
    });

    test('keeps the aspect ratio when only one dimension is capped', () async {
      final result = await PlatformImageEncoder.encodeWebP(
        _png(width: 300, height: 150),
        maxWidth: 150,
      );
      expect(result, isNotNull);
      final decoded = img.decodeImage(result!)!;
      expect(decoded.width, lessThanOrEqualTo(150));
      expect(decoded.height, 75, reason: '2:1 source ratio is preserved');
    });
  });
}
