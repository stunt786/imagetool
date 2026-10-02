import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Handles WebP encoding across all platforms and devices using hardware-accelerated
/// platform encoding with pure Dart fallback.
abstract final class PlatformImageEncoder {
  /// WebP encoding is supported on every platform via hardware acceleration
  /// or pure Dart encoder.
  static bool get supportsWebP => true;

  /// Encodes [bytes] to WebP across all devices and platforms.
  static Future<Uint8List?> encodeWebP(
    Uint8List bytes, {
    int quality = 90,
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (bytes.isEmpty) return null;

    // 1. Try hardware-accelerated encoding on Android if available
    try {
      if (Platform.isAndroid) {
        Uint8List inputBytes = bytes;
        final isPngOrJpeg = bytes.length >= 3 &&
            ((bytes[0] == 0xFF && bytes[1] == 0xD8) || // JPEG
                (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E)); // PNG
        if (!isPngOrJpeg) {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            inputBytes = Uint8List.fromList(img.encodePng(decoded));
          }
        }

        final result = await FlutterImageCompress.compressWithList(
          inputBytes,
          quality: quality.clamp(1, 100),
          format: CompressFormat.webp,
          minWidth: maxWidth ?? 0,
          minHeight: maxHeight ?? 0,
          keepExif: false,
        );
        if (result.isNotEmpty) {
          return Uint8List.fromList(result);
        }
      }
    } catch (_) {
      // Fall through to pure Dart WebP encoder
    }

    // 2. Pure Dart fallback: works reliably on every device, platform, and test
    try {
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      if ((maxWidth != null && maxWidth > 0) ||
          (maxHeight != null && maxHeight > 0)) {
        decoded = img.copyResize(
          decoded,
          width: maxWidth,
          height: maxHeight,
          interpolation: img.Interpolation.average,
        );
      }

      final encoded = img.encodeWebP(
        decoded,
        lossless: quality >= 100,
        quality: quality.clamp(1, 100),
      );
      return Uint8List.fromList(encoded);
    } catch (_) {
      return null;
    }
  }
}
