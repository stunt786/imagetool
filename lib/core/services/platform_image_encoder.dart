import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Wraps the platform image encoders that the pure-Dart `image` package does
/// not provide.
///
/// `flutter_image_compress` is already a dependency of this app; this service
/// centralises the platform checks so features can ask "can this device write
/// WebP?" instead of silently writing PNG bytes into a `.webp` file.
abstract final class PlatformImageEncoder {
  /// WebP encoding is only implemented by the Android plugin implementation.
  static bool get supportsWebP {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Encodes [bytes] to WebP, or returns null when unsupported on this device.
  static Future<Uint8List?> encodeWebP(
    Uint8List bytes, {
    int quality = 90,
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (!supportsWebP || bytes.isEmpty) return null;
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: quality.clamp(1, 100),
        format: CompressFormat.webp,
        minWidth: maxWidth ?? 0,
        minHeight: maxHeight ?? 0,
        keepExif: false,
      );
      if (result.isEmpty) return null;
      return Uint8List.fromList(result);
    } catch (_) {
      return null;
    }
  }
}
