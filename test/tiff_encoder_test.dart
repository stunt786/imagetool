import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/utils/tiff_encoder.dart';

void main() {
  group('Standard baseline TIFF 6.0 encoder', () {
    test('encodes RGB image into valid TIFF 6.0 format', () {
      final image = img.Image(width: 100, height: 80);
      img.fill(image, color: img.ColorRgb8(255, 0, 128));

      final bytes = encodeStandardTiff(image);
      expect(bytes, isNotEmpty);

      // Verify TIFF header
      final byteData = ByteData.sublistView(bytes);
      final magic = byteData.getUint16(0, Endian.little);
      expect(magic, 0x4949); // 'II' (little-endian)
      final version = byteData.getUint16(2, Endian.little);
      expect(version, 42);
      final ifdOffset = byteData.getUint32(4, Endian.little);
      expect(ifdOffset, 8);

      // Verify number of IFD entries
      final numEntries = byteData.getUint16(ifdOffset, Endian.little);
      expect(numEntries, 12);

      // Verify that img.decodeImage decodes the encoded TIFF correctly
      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 100);
      expect(decoded.height, 80);
      expect(decoded.getPixel(50, 40).r.toInt(), 255);
      expect(decoded.getPixel(50, 40).g.toInt(), 0);
      expect(decoded.getPixel(50, 40).b.toInt(), 128);
    });

    test('handles RGBA image with transparency by converting to RGB', () {
      final image = img.Image(width: 50, height: 50, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 255));

      final bytes = encodeStandardTiff(image);
      expect(bytes, isNotEmpty);

      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 50);
      expect(decoded.height, 50);
      expect(decoded.numChannels, 3);
      expect(decoded.getPixel(10, 10).r.toInt(), 10);
      expect(decoded.getPixel(10, 10).g.toInt(), 20);
      expect(decoded.getPixel(10, 10).b.toInt(), 30);
    });
  });
}
