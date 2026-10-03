import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/services/image_filter_service.dart';

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

img.Image _solid(int width, int height, int gray) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, gray, gray, gray, 255);
    }
  }
  return image;
}

/// White page with a few thin dark "text" bars.
img.Image _documentPage(int size) {
  final image = _solid(size, size, 240);
  for (final top in [size ~/ 4, size ~/ 2, 3 * size ~/ 4]) {
    for (var y = top; y < top + 4 && y < size; y++) {
      for (var x = size ~/ 10; x < size * 9 ~/ 10; x++) {
        image.setPixelRgba(x, y, 40, 40, 40, 255);
      }
    }
  }
  return image;
}

img.Image _halfSplit(int size, {int left = 100, int right = 230}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final v = x < size ~/ 2 ? left : right;
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return image;
}

img.Image _gradient(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (40 + x * 180 / width).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return image;
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

double _meanChannelRegion(img.Image image, int x0, int x1) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = x0; x < x1; x++) {
      sum += image.getPixel(x, y).r.toDouble();
      count++;
    }
  }
  return sum / count;
}

/// Fraction of pixels sitting close to pure black or pure white.
double _binaryFraction(img.Image image) {
  var total = 0;
  var nearBinary = 0;
  for (final p in image) {
    total++;
    final r = p.r.toInt();
    if ((r - 0).abs() <= 40 || (r - 255).abs() <= 40) nearBinary++;
  }
  return nearBinary / total;
}

int _warmPixelCount(img.Image image) {
  var count = 0;
  for (final p in image) {
    if (p.r > 150 && p.g < 130 && p.b < 130) count++;
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageFilterService entry points', () {
    test('FilterType.none is not a filter and returns null', () async {
      final bytes = _png(_documentPage(64));
      expect(await ImageFilterService.applyFilter(bytes, FilterType.none),
          isNull);
      expect(await ImageFilterService.applyPreview(bytes, FilterType.none),
          isNull);
    });

    test('undecodable bytes return null', () async {
      final junk = Uint8List.fromList(List<int>.filled(100, 9));
      expect(
          await ImageFilterService.applyFilter(junk, FilterType.grayscale),
          isNull);
      expect(
          await ImageFilterService.applyPreview(junk, FilterType.grayscale),
          isNull);
      expect(await ImageFilterService.rotate90(junk), isNull);
      expect(await ImageFilterService.applyBinarization(junk), isNull);
    });

    test('previews are capped to 900px on the longest edge', () async {
      final bytes = _png(_gradient(1000, 600));
      final result = await ImageFilterService.applyPreview(
          bytes, FilterType.grayscale);

      expect(result, isNotNull);
      expect(result!.width, 900);
      expect(result.height, 540);
      expect(img.decodeImage(result.bytes)!.width, 900);
    });

    test('previews of small images keep the source dimensions', () async {
      final bytes = _png(_documentPage(80));
      final result =
          await ImageFilterService.applyPreview(bytes, FilterType.sepia);

      expect(result, isNotNull);
      expect(result!.width, 80);
      expect(result.height, 80);
    });
  });

  group('ImageFilterService rotations', () {
    Uint8List markerImage() {
      final image = _solid(60, 40, 235);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          image.setPixelRgba(x, y, 220, 40, 40, 255);
        }
      }
      return _png(image);
    }

    test('rotate90 and rotate270 swap the dimensions', () async {
      final bytes = markerImage();

      final cw = await ImageFilterService.rotate90(bytes);
      expect(cw, isNotNull);
      expect(cw!.width, 40);
      expect(cw.height, 60);

      final ccw = await ImageFilterService.rotate270(bytes);
      expect(ccw, isNotNull);
      expect(ccw!.width, 40);
      expect(ccw.height, 60);
    });

    test('rotations keep the marked pixels', () async {
      final bytes = markerImage();
      final before = _warmPixelCount(img.decodeImage(bytes)!);
      expect(before, greaterThan(20));

      final cw = await ImageFilterService.rotate90(bytes);
      final ccw = await ImageFilterService.rotate270(bytes);

      expect(
        _warmPixelCount(img.decodeImage(cw!.bytes)!),
        greaterThan(before ~/ 2),
      );
      expect(
        _warmPixelCount(img.decodeImage(ccw!.bytes)!),
        greaterThan(before ~/ 2),
      );
    });

    test('a quarter turn followed by the opposite one restores the size',
        () async {
      final bytes = markerImage();
      final cw = await ImageFilterService.rotate90(bytes);
      final back = await ImageFilterService.rotate270(cw!.bytes);

      expect(back, isNotNull);
      expect(back!.width, 60);
      expect(back.height, 40);
    });
  });

  group('ImageFilterService pixel statistics', () {
    test('binarization collapses the page to black and white', () async {
      final bytes = _png(_documentPage(80));

      final result = await ImageFilterService.applyBinarization(bytes);
      expect(result, isNotNull);
      final out = img.decodeImage(result!.bytes)!;
      expect(out.width, 80);
      expect(out.height, 80);

      expect(_binaryFraction(out), greaterThan(0.6));
      expect(_meanChannel(out), greaterThan(150),
          reason: 'the page stays mostly white after thresholding');

      // The text bars survive as dark pixels.
      var dark = 0;
      for (final p in out) {
        if (p.r < 80) dark++;
      }
      expect(dark / (80 * 80), inInclusiveRange(0.02, 0.35));
    });

    test('grayscale makes every channel agree', () async {
      final image = img.Image(width: 48, height: 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 48; x++) {
          image.setPixelRgba(x, y, (x * 5) % 256, (y * 7) % 256, 128, 255);
        }
      }
      final result =
          await ImageFilterService.applyFilter(_png(image), FilterType.grayscale);
      expect(result, isNotNull);

      final out = img.decodeImage(result!.bytes)!;
      var offChannel = 0;
      for (final p in out) {
        if ((p.r - p.g).abs() > 12 || (p.g - p.b).abs() > 12) offChannel++;
      }
      expect(offChannel / (48 * 48), lessThan(0.02));
    });

    test('lighten raises the average luminance', () async {
      final bytes = _png(_solid(48, 48, 140));
      final before = _meanChannel(img.decodeImage(bytes)!);

      final result =
          await ImageFilterService.applyFilter(bytes, FilterType.lighten);
      expect(result, isNotNull);
      final after = _meanChannel(img.decodeImage(result!.bytes)!);

      expect(after, greaterThan(before + 20));
    });

    test('invert flips the average luminance', () async {
      final bytes = _png(_documentPage(64));
      final before = _meanChannel(img.decodeImage(bytes)!);

      final result =
          await ImageFilterService.applyFilter(bytes, FilterType.invert);
      expect(result, isNotNull);
      final after = _meanChannel(img.decodeImage(result!.bytes)!);

      expect(after, closeTo(255 - before, 25));
    });

    test('sepia and enhance keep the output dimensions', () async {
      final bytes = _png(_documentPage(56));
      for (final filter in [FilterType.sepia, FilterType.enhance]) {
        final result = await ImageFilterService.applyFilter(bytes, filter);
        expect(result, isNotNull, reason: '$filter produced no output');
        expect(result!.width, 56);
        expect(result.height, 56);
        final decoded = img.decodeImage(result.bytes)!;
        expect(decoded.width, 56);
        expect(decoded.height, 56);
      }
    });

    test('direct magic color keeps the geometry and brightens the page',
        () async {
      final bytes = _png(_documentPage(72));
      final before = _meanChannel(img.decodeImage(bytes)!);

      final result = await ImageFilterService.applyMagicColor(bytes);
      expect(result, isNotNull);
      final out = img.decodeImage(result!.bytes)!;
      expect(out.width, 72);
      expect(out.height, 72);
      expect(_meanChannel(out), greaterThan(before - 30));
      expect(_meanChannel(out), lessThan(255));
    });

    test('shadow removal flattens uneven lighting', () async {
      final bytes = _png(_halfSplit(96));
      final source = img.decodeImage(bytes)!;
      final beforeGap =
          (_meanChannelRegion(source, 48, 96) - _meanChannelRegion(source, 0, 48))
              .abs();

      final result = await ImageFilterService.applyShadowRemoval(bytes);
      expect(result, isNotNull);
      final out = img.decodeImage(result!.bytes)!;
      expect(out.width, 96);
      expect(out.height, 96);

      final left = _meanChannelRegion(out, 0, 48);
      final right = _meanChannelRegion(out, 48, 96);
      expect((right - left).abs(), lessThan(beforeGap * 0.4),
          reason: 'the shadow seam must be levelled');
      expect(left, greaterThan(160), reason: 'the dark side is lifted');
    });

    test('auto brighten lifts an underexposed page', () async {
      final bytes = _png(_solid(64, 64, 70));
      final before = _meanChannel(img.decodeImage(bytes)!);

      final result =
          await ImageFilterService.applyFilter(bytes, FilterType.autoBrighten);
      expect(result, isNotNull);
      final after = _meanChannel(img.decodeImage(result!.bytes)!);
      expect(after, greaterThan(before + 40));
    });
  });
}
