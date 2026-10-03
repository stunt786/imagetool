import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/services/document_enhancement_service.dart';

img.Image _solid(int width, int height, int gray) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, gray, gray, gray, 255);
    }
  }
  return image;
}

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

/// Dark table with a white page in the middle of the frame.
img.Image _framedPage(int size) {
  final image = _solid(size, size, 35);
  for (var y = size ~/ 6; y < size - size ~/ 6; y++) {
    for (var x = size ~/ 6; x < size - size ~/ 6; x++) {
      image.setPixelRgba(x, y, 240, 240, 240, 255);
    }
  }
  return image;
}

img.Image _gradient(int width, int height, {int from = 60, int to = 230}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (from + (to - from) * x / width).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return image;
}

double _mean(img.Image image) {
  var sum = 0.0;
  var count = 0;
  for (final p in image) {
    sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    count++;
  }
  return sum / count;
}

double _stddevOfColumnMeans(img.Image image) {
  final columnMeans = <double>[];
  for (var x = 0; x < image.width; x++) {
    var sum = 0.0;
    for (var y = 0; y < image.height; y++) {
      sum += image.getPixel(x, y).r.toDouble();
    }
    columnMeans.add(sum / image.height);
  }
  final mean = columnMeans.reduce((a, b) => a + b) / columnMeans.length;
  final variance = columnMeans
          .map((v) => (v - mean) * (v - mean))
          .reduce((a, b) => a + b) /
      columnMeans.length;
  return math.sqrt(variance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('document corner detection', () {
    test('internalDetectPaperCorners boxes in the page of a framed scan',
        () {
      final corners =
          DocumentEnhancementService.internalDetectPaperCorners(_framedPage(120));

      expect(corners, hasLength(4));
      for (final corner in corners) {
        expect(corner.dx, inInclusiveRange(0.0, 1.0));
        expect(corner.dy, inInclusiveRange(0.0, 1.0));
      }
      // TL, TR, BR, BL ordering.
      expect(corners[0].dx, lessThan(corners[1].dx));
      expect(corners[0].dy, corners[1].dy);
      expect(corners[2].dx, corners[1].dx);
      expect(corners[0].dy, lessThan(corners[2].dy));
      expect(corners[3].dx, corners[0].dx);

      // The page starts around 1/6 of the frame and ends around 5/6.
      expect(corners[0].dx, inInclusiveRange(0.05, 0.35));
      expect(corners[1].dx, inInclusiveRange(0.65, 0.95));
      expect(corners[0].dy, inInclusiveRange(0.05, 0.35));
      expect(corners[2].dy, inInclusiveRange(0.65, 0.95));
    });

    test('detectDocumentCorners runs in an isolate and normalizes', () async {
      final corners = await DocumentEnhancementService.detectDocumentCorners(
        _png(_framedPage(120)),
      );

      expect(corners, hasLength(4));
      for (final corner in corners) {
        expect(corner.dx, inInclusiveRange(0.0, 1.0));
        expect(corner.dy, inInclusiveRange(0.0, 1.0));
      }
      expect(corners[0].dx, lessThan(corners[1].dx));
      expect(corners[0].dy, lessThan(corners[2].dy));
    });

    test('detectDocumentCorners falls back to the default quad', () async {
      final corners = await DocumentEnhancementService.detectDocumentCorners(
        Uint8List.fromList(List<int>.filled(64, 3)),
      );

      expect(corners, hasLength(4));
      expect(corners[0], const Offset(0.05, 0.05));
      expect(corners[1], const Offset(0.95, 0.05));
      expect(corners[2], const Offset(0.95, 0.95));
      expect(corners[3], const Offset(0.05, 0.95));
    });
  });

  group('uneven illumination probe', () {
    test('an evenly lit page is reported as even', () {
      expect(
        DocumentEnhancementService.internalHasUnevenIllumination(
            _solid(120, 120, 235)),
        isFalse,
      );
    });

    test('a strongly graded page is reported as uneven', () {
      expect(
        DocumentEnhancementService.internalHasUnevenIllumination(
            _gradient(120, 120)),
        isTrue,
      );
    });
  });

  group('brightness and shadow correction', () {
    test('a dark page is brightened and a bright page is left alone', () {
      final dark = _solid(100, 100, 55);
      final brightened =
          DocumentEnhancementService.internalAutoAdjustDarkImage(dark);
      expect(_mean(brightened), greaterThan(_mean(dark) + 40));

      final bright = _solid(100, 100, 235);
      final untouched =
          DocumentEnhancementService.internalAutoAdjustDarkImage(bright);
      expect(identical(untouched, bright), isTrue,
          reason: 'a well exposed page must not be re-processed');
    });

    test('anti-light correction levels a horizontal gradient', () {
      final uneven = _gradient(120, 120);
      final before = _stddevOfColumnMeans(uneven);
      expect(before, greaterThan(40));

      final corrected =
          DocumentEnhancementService.internalAutocorrectAntiLightShadows(uneven);

      expect(corrected.width, uneven.width);
      expect(corrected.height, uneven.height);
      expect(_stddevOfColumnMeans(corrected), lessThan(before * 0.5),
          reason: 'the illumination gradient must flatten');
      expect(corrected.getPixel(4, 60).r, greaterThan(uneven.getPixel(4, 60).r),
          reason: 'the dark side is lifted towards paper white');
    });

    test('autoAdjustDarkImage wrapper output is brighter', () async {
      final bytes = _png(_solid(80, 80, 55));
      final result = await DocumentEnhancementService.autoAdjustDarkImage(bytes);

      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(out.width, 80);
      expect(out.height, 80);
      expect(_mean(out), greaterThan(_mean(img.decodeImage(bytes)!) + 40));
    });

    test('autocorrectAntiLightShadows wrapper keeps the geometry', () async {
      final bytes = _png(_gradient(96, 72));
      final result =
          await DocumentEnhancementService.autocorrectAntiLightShadows(bytes);

      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(out.width, 96);
      expect(out.height, 72);
      expect(_stddevOfColumnMeans(out), lessThan(_stddevOfColumnMeans(img.decodeImage(bytes)!)));
    });
  });

  group('auto fit / flatten pipeline', () {
    test('internalAutoFitPaper crops a framed page down to the paper', () {
      final framed = _framedPage(180);
      final fitted = DocumentEnhancementService.internalAutoFitPaper(framed);

      expect(fitted.width, lessThan(framed.width));
      expect(fitted.height, lessThan(framed.height));
      expect(fitted.width, greaterThan(80));
      expect(fitted.height, greaterThan(80));
      expect(fitted.getPixel(fitted.width ~/ 2, fitted.height ~/ 2).r,
          greaterThan(180),
          reason: 'the crop must be centred on the paper');
    });

    test('internalAutoFitPaper leaves a full-bleed page untouched', () {
      final fullBleed = _solid(140, 140, 240);
      final fitted = DocumentEnhancementService.internalAutoFitPaper(fullBleed);
      expect(identical(fitted, fullBleed), isTrue);
    });

    test('autoFitToPaper wrapper returns a smaller image for a framed scan',
        () async {
      final bytes = _png(_framedPage(160));
      final result = await DocumentEnhancementService.autoFitToPaper(bytes);

      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(out.width, lessThan(160));
      expect(out.height, lessThan(160));
    });

    test('flattenDocument and autoFlattenBendedPaper return usable images',
        () async {
      final bytes = _png(_framedPage(120));

      final flattened = await DocumentEnhancementService.flattenDocument(bytes);
      expect(flattened, isNotNull);
      final flatImage = img.decodeImage(flattened!)!;
      expect(flatImage.width, greaterThan(0));
      expect(flatImage.height, greaterThan(0));

      final bended =
          await DocumentEnhancementService.autoFlattenBendedPaper(bytes);
      expect(bended, isNotNull);
      expect(img.decodeImage(bended!)!.width, greaterThan(0));
    });
  });

  group('smart clean stages', () {
    test('a clean bright page only needs background cleaning', () async {
      final result = await DocumentEnhancementService.smartScanEnhanceDetailed(
        _png(_solid(120, 120, 240)),
      );

      expect(result, isNotNull);
      expect(result!.stages, isNotEmpty);
      expect(result.stages, contains('Background cleaned'));
      expect(result.stages, isNot(contains('Shadows removed')));
      expect(result.stages, isNot(contains('Brightness')));
      expect(img.decodeImage(result.bytes)!.width, 120);
    });

    test('a dark page also runs the brightness stage', () async {
      final result = await DocumentEnhancementService.smartScanEnhanceDetailed(
        _png(_solid(120, 120, 55)),
      );

      expect(result, isNotNull);
      expect(result!.stages, contains('Background cleaned'));
      expect(result.stages, contains('Brightness'));
      final out = img.decodeImage(result.bytes)!;
      expect(_mean(out), greaterThan(150),
          reason: 'the dark page must come out bright');
    });

    test('undecodable input yields no smart enhance result', () async {
      final result = await DocumentEnhancementService.smartScanEnhanceDetailed(
        Uint8List.fromList(List<int>.filled(40, 1)),
      );
      expect(result, isNull);
    });
  });
}
