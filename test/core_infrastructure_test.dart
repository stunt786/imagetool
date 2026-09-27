import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_progress.dart';
import 'package:pixeltools/core/progress/operation_progress_controller.dart';
import 'package:pixeltools/core/services/image_isolate_service.dart';
import 'package:pixeltools/core/utils/file_type_detector.dart';

Uint8List _pngHeader() => Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    ]);

Uint8List _jpegHeader() =>
    Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

Uint8List _webpHeader() => Uint8List.fromList(<int>[
      0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
    ]);

Uint8List _pdfHeader() =>
    Uint8List.fromList('%PDF-1.4\n'.codeUnits);

void main() {
  group('FileTypeDetector', () {
    test('trusts the header over a misleading extension', () {
      final type = FileTypeDetector.detect(
        name: 'photo.jpg',
        bytes: _pngHeader(),
      );
      expect(type.kind, AppFileKind.image);
      expect(type.imageFormat, 'png');
      expect(type.mimeType, 'image/png');
    });

    test('detects PDF from the header', () {
      final type = FileTypeDetector.detect(name: 'scan', bytes: _pdfHeader());
      expect(type.isPdf, isTrue);
      expect(type.mimeType, 'application/pdf');
    });

    test('falls back to the extension when bytes are unavailable', () {
      final type = FileTypeDetector.detect(name: 'holiday.JPEG');
      expect(type.isImage, isTrue);
      expect(type.imageFormat, 'jpg');
    });

    test('recognises WebP and HEIC signatures', () {
      expect(
        FileTypeDetector.imageFormatFromSignature(_webpHeader()),
        'webp',
      );
      final heic = Uint8List.fromList(<int>[
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, 0x63,
      ]);
      expect(FileTypeDetector.imageFormatFromSignature(heic), 'heic');
    });

    test('treats JPG and JPEG as the same codec', () {
      expect(
        FileTypeDetector.isAlreadyInFormat(
          targetExtension: 'jpeg',
          name: 'photo.jpg',
          bytes: _jpegHeader(),
        ),
        isTrue,
      );
      expect(
        FileTypeDetector.isAlreadyInFormat(
          targetExtension: 'png',
          name: 'photo.jpg',
          bytes: _jpegHeader(),
        ),
        isFalse,
      );
      expect(
        FileTypeDetector.isAlreadyInFormat(
          targetExtension: 'jpg',
          name: 'photo.png',
          bytes: _pngHeader(),
        ),
        isFalse,
      );
    });

    test('normalises extension aliases', () {
      expect(FileTypeDetector.canonicalImageExtension('JPEG'), 'jpg');
      expect(FileTypeDetector.canonicalImageExtension('.tif'), 'tiff');
      expect(FileTypeDetector.canonicalImageExtension('heif'), 'heic');
      expect(FileTypeDetector.canonicalImageExtension('exe'), isNull);
    });

    test('labels file types for badges', () {
      final pdf = FileTypeDetector.detect(name: 'doc.pdf');
      expect(FileTypeDetector.labelFor(pdf), 'PDF');
    });
  });

  group('OperationProgress', () {
    test('reports a real fraction and counter', () {
      const progress = OperationProgress(
        total: 9,
        completed: 6,
        isIndeterminate: false,
      );
      expect(progress.fraction, closeTo(2 / 3, 0.0001));
      expect(progress.percent, 67);
      expect(progress.counterLabel, '6 of 9');
    });

    test('never invents a percentage when the total is unknown', () {
      const progress = OperationProgress(statusText: 'Processing...');
      expect(progress.fraction, isNull);
      expect(progress.percent, isNull);
      expect(progress.counterLabel, isNull);
    });

    test('clamps out-of-range counters', () {
      const over = OperationProgress(
        total: 3,
        completed: 5,
        isIndeterminate: false,
      );
      expect(over.fraction, 1.0);
      const under = OperationProgress(
        total: 3,
        completed: 0,
        isIndeterminate: false,
      );
      expect(under.fraction, 0.0);
    });
  });

  group('OperationProgressController', () {
    test('tracks state and completes', () {
      final controller = OperationProgressController();
      addTearDown(controller.dispose);

      controller.start(title: 'Converting images', total: 4, canCancel: true);
      controller.begin();
      controller.step(statusText: 'Converted 1 of 4');
      expect(controller.progress.completed, 1);
      expect(controller.progress.isActive, isTrue);
      expect(controller.progress.canCancel, isTrue);

      controller.step(by: 3);
      controller.complete();
      expect(controller.progress.status, OperationStatus.completed);
      expect(controller.progress.fraction, 1.0);
      expect(controller.progress.canCancel, isFalse);
    });

    test('cancellation is cooperative', () {
      final controller = OperationProgressController();
      addTearDown(controller.dispose);

      controller.start(title: 'Loading', total: 10, canCancel: true);
      expect(controller.isCancelled, isFalse);
      controller.throwIfCancelled();

      controller.cancel();
      expect(controller.isCancelled, isTrue);
      expect(controller.progress.status, OperationStatus.cancelled);
      expect(
        controller.throwIfCancelled,
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('starting again clears a previous cancellation', () {
      final controller = OperationProgressController();
      addTearDown(controller.dispose);
      controller.start(title: 'A', total: 1, canCancel: true);
      controller.cancel();
      expect(controller.isCancelled, isTrue);
      controller.start(title: 'B', total: 2);
      expect(controller.isCancelled, isFalse);
    });
  });

  group('ImageIsolateService.mapConcurrent', () {
    test('preserves input order', () async {
      final items = List<int>.generate(20, (i) => i);
      final results = await ImageIsolateService.mapConcurrent<int, int>(
        items,
        (item, index) async {
          await Future<void>.delayed(
            Duration(milliseconds: (20 - item) % 5),
          );
          return item * 2;
        },
        concurrency: 3,
      );
      expect(results, items.map((i) => i * 2).toList());
    });

    test('respects the concurrency cap', () async {
      var inFlight = 0;
      var peak = 0;
      final results = await ImageIsolateService.mapConcurrent<int, int>(
        List<int>.generate(12, (i) => i),
        (item, index) async {
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return item;
        },
        concurrency: 2,
      );
      expect(results.length, 12);
      expect(peak, lessThanOrEqualTo(2));
    });

    test('stops queueing new work once cancelled', () async {
      var started = 0;
      var cancelled = false;
      final results = await ImageIsolateService.mapConcurrent<int, int>(
        List<int>.generate(50, (i) => i),
        (item, index) async {
          started++;
          if (started >= 4) cancelled = true;
          return item;
        },
        concurrency: 2,
        isCancelled: () => cancelled,
      );
      expect(started, lessThan(50));
      expect(results.length, 50);
      expect(results.where((r) => r != null).length, started);
    });

    test('reports real progress counts', () async {
      final seen = <int>[];
      await ImageIsolateService.mapConcurrent<int, int>(
        List<int>.generate(5, (i) => i),
        (item, index) async => item,
        concurrency: 2,
        onProgress: (completed, total) => seen.add(completed),
      );
      expect(seen.last, 5);
      expect(seen, isNotEmpty);
    });
  });

  group('ImageIsolateService image pipeline', () {
    test('probe reads dimensions and format from the header', () async {
      final source = img.Image(width: 640, height: 480);
      final encoded = Uint8List.fromList(img.encodeJpg(source));

      final probe = await ImageIsolateService.probe(encoded);
      expect(probe.isValid, isTrue);
      expect(probe.width, 640);
      expect(probe.height, 480);
      expect(probe.format, 'jpg');
    });

    test('probe rejects data that is not an image', () async {
      final probe = await ImageIsolateService.probe(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );
      expect(probe.isValid, isFalse);
    });

    test('thumbnail downscales without upscaling', () async {
      final source = img.Image(width: 900, height: 600);
      img.fill(source, color: img.ColorRgb8(10, 120, 200));
      final encoded = Uint8List.fromList(img.encodePng(source));

      final thumb = await ImageIsolateService.thumbnail(encoded, maxSide: 200);
      expect(thumb, isNotNull);
      final decoded = img.decodeImage(thumb!);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(200));
      expect(decoded.height, lessThanOrEqualTo(200));
      expect(decoded.width, greaterThan(0));
    });

    test('thumbnail returns null for corrupt data', () async {
      final result = await ImageIsolateService.thumbnail(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      );
      expect(result, isNull);
    });

    test('transform never upscales a smaller image', () async {
      final source = img.Image(width: 100, height: 80);
      final encoded = Uint8List.fromList(img.encodePng(source));
      final result = await ImageIsolateService.transform(
        encoded,
        const ImageTransformRequest(
          targetExtension: 'jpg',
          maxWidth: 1280,
          maxHeight: 1280,
        ),
      );
      expect(result, isNotNull);
      final decoded = img.decodeImage(result!);
      expect(decoded!.width, 100);
      expect(decoded.height, 80);
    });
  });
}
