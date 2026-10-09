import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/format_converter/notifiers/format_converter_notifier.dart';

void main() {
  group('FormatConverter conversion worker', () {
    test('converts PNG to TIFF using standard TIFF encoder', () async {
      final image = img.Image(width: 80, height: 60);
      img.fill(image, color: img.ColorRgb8(0, 200, 100));
      final sourceBytes = Uint8List.fromList(img.encodePng(image));

      final convertedBytes = await convertFormatWorker(<String, Object?>{
        'source': sourceBytes,
        'target': 'tiff',
        'quality': 90,
      });

      expect(convertedBytes, isNotNull);
      expect(convertedBytes, isNotEmpty);

      // Verify TIFF decodability and dimensions
      final decodedTiff = img.decodeImage(convertedBytes!);
      expect(decodedTiff, isNotNull);
      expect(decodedTiff!.width, 80);
      expect(decodedTiff.height, 60);
      expect(decodedTiff.getPixel(40, 30).r.toInt(), 0);
      expect(decodedTiff.getPixel(40, 30).g.toInt(), 200);
      expect(decodedTiff.getPixel(40, 30).b.toInt(), 100);
    });

    test('converts JPEG to TIFF properly', () async {
      final image = img.Image(width: 40, height: 40);
      img.fill(image, color: img.ColorRgb8(120, 80, 240));
      final sourceBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));

      final convertedBytes = await convertFormatWorker(<String, Object?>{
        'source': sourceBytes,
        'target': 'tif',
        'quality': 90,
      });

      expect(convertedBytes, isNotNull);
      expect(convertedBytes, isNotEmpty);

      final decoded = img.decodeImage(convertedBytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 40);
      expect(decoded.height, 40);
    });
  });

  group('FormatConverterState', () {
    test('tracks converted count and success metrics accurately', () {
      const state = FormatConverterState(
        images: [
          ConvertibleImage(
            id: '1',
            name: 'photo1.jpg',
            path: '/path/photo1.jpg',
            sizeBytes: 1000,
            originalFormat: 'jpg',
            status: ConvertStatus.success,
          ),
          ConvertibleImage(
            id: '2',
            name: 'photo2.png',
            path: '/path/photo2.png',
            sizeBytes: 2000,
            originalFormat: 'png',
            status: ConvertStatus.failed,
          ),
          ConvertibleImage(
            id: '3',
            name: 'photo3.webp',
            path: '/path/photo3.webp',
            sizeBytes: 3000,
            originalFormat: 'webp',
            status: ConvertStatus.ready,
          ),
        ],
      );

      expect(state.totalImages, 3);
      expect(state.successCount, 1);
      expect(state.failedCount, 1);
      expect(state.pendingCount, 1);
      expect(state.hasWork, isTrue);
    });
  });
}
