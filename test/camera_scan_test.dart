import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/notifiers/document_batch_notifier.dart';
import 'package:pixeltools/features/camera/services/document_enhancement_service.dart';
import 'package:pixeltools/features/camera/services/image_filter_service.dart';

Uint8List _createSampleImageBytes() {
  final image = img.Image(width: 80, height: 80);
  for (var y = 0; y < 80; y++) {
    for (var x = 0; x < 80; x++) {
      if (y >= 30 && y <= 50 && x >= 20 && x <= 60) {
        image.setPixelRgba(x, y, 20, 20, 20, 255); // Text
      } else {
        image.setPixelRgba(x, y, 230, 230, 230, 255); // White page
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

bool _isImageBlack(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return true;
  var allZero = true;
  for (final pixel in decoded) {
    if (pixel.r > 10 || pixel.g > 10 || pixel.b > 10) {
      allZero = false;
      break;
    }
  }
  return allZero;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List sampleBytes;
  late Directory tempDir;
  late File sampleFile;

  setUpAll(() async {
    sampleBytes = _createSampleImageBytes();
    tempDir = await Directory.systemTemp.createTemp('camera_test_');
    sampleFile = File('${tempDir.path}/test_scan.jpg');
    await sampleFile.writeAsBytes(sampleBytes);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Camera scan and document batch notifier tests', () {
    test('addPageFromPath keeps original image without auto-darkening or filter', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.addPageFromPath(sampleFile.path);

      final batch = container.read(documentBatchProvider);
      expect(batch.pages.length, equals(1));

      final page = batch.pages.first;
      expect(page.filterType, equals(FilterType.none));
      expect(page.filteredBytes, isNull);
      expect(page.displayBytes.isNotEmpty, isTrue);

      // Verify the page display bytes are NOT black
      expect(_isImageBlack(page.displayBytes), isFalse);
    });

    test('All image filters produce non-black output', () async {
      final filtersToTest = [
        FilterType.magicColor,
        FilterType.shadowRemoval,
        FilterType.lighten,
        FilterType.enhance,
        FilterType.noShadow,
        FilterType.eco,
        FilterType.grayscale,
        FilterType.invert,
        FilterType.sepia,
        FilterType.warm,
        FilterType.cool,
        FilterType.dramatic,
        FilterType.blackWhite,
        FilterType.binarization,
        FilterType.bwHighContrast,
        FilterType.autoFlatten,
        FilterType.antiLight,
        FilterType.autoBrighten,
        FilterType.smartScan,
      ];

      for (final filter in filtersToTest) {
        final result = await ImageFilterService.applyFilter(sampleBytes, filter);
        expect(result, isNotNull, reason: 'Filter $filter returned null result');
        expect(result!.bytes.isNotEmpty, isTrue);
        expect(
          _isImageBlack(result.bytes),
          isFalse,
          reason: 'Filter $filter turned image into a black screen',
        );
      }
    });

    test('ImageFilterService.applyPreview produces non-black output', () async {
      final result = await ImageFilterService.applyPreview(
        sampleBytes,
        FilterType.shadowRemoval,
      );
      expect(result, isNotNull);
      expect(_isImageBlack(result!.bytes), isFalse);
    });

    test('DocumentEnhancementService auto-enhancement pipeline functions correctly', () async {
      // 1. Test dark image correction
      final darkImage = img.Image(width: 80, height: 80);
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          darkImage.setPixelRgba(x, y, 50, 50, 50, 255);
        }
      }
      final brightened = DocumentEnhancementService.internalAutoAdjustDarkImage(darkImage);
      expect(brightened.getPixel(40, 40).r, greaterThan(50));

      // 2. Test antilight shadow autocorrection
      final unevenImage = img.Image(width: 80, height: 80);
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          final factor = (x / 80.0) * 0.8 + 0.2;
          unevenImage.setPixelRgba(x, y, (200 * factor).toInt(), (200 * factor).toInt(), (200 * factor).toInt(), 255);
        }
      }
      final shadowCorrected = DocumentEnhancementService.internalAutocorrectAntiLightShadows(unevenImage);
      expect(shadowCorrected.width, equals(80));
      expect(shadowCorrected.height, equals(80));

      // 3. Test dewarping / auto-flattening
      final flat = DocumentEnhancementService.internalAutoFlattenPaper(unevenImage);
      expect(flat.width, equals(80));
      expect(flat.height, equals(80));

      // 4. Test smartScanEnhance isolate orchestration
      final fullResult = await DocumentEnhancementService.smartScanEnhance(sampleBytes);
      expect(fullResult, isNotNull);
      expect(fullResult!.isNotEmpty, isTrue);
      expect(_isImageBlack(fullResult), isFalse);
    });
  });
}
