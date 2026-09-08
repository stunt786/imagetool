import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/settings/app_settings.dart';

/// Helper service for drawing global watermarks on image bytes and decoded images.
class WatermarkHelper {
  WatermarkHelper._();

  /// Applies global watermark to [imageBytes] if enabled in [settings].
  /// Returns modified image bytes or original [imageBytes] if disabled.
  static Uint8List applyGlobalWatermarkIfNeeded(
    Uint8List imageBytes,
    AppSettingsState settings,
  ) {
    if (!settings.enableGlobalWatermark || imageBytes.isEmpty) {
      return imageBytes;
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;

    final watermarked = applyToImage(decoded, settings);

    // Re-encode image (preserve PNG header if present, otherwise encode JPEG)
    if (imageBytes.length > 8 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4E &&
        imageBytes[3] == 0x47) {
      return Uint8List.fromList(img.encodePng(watermarked));
    }
    return Uint8List.fromList(img.encodeJpg(watermarked, quality: 95));
  }

  /// Draws watermark text directly onto an [img.Image] instance based on [settings].
  static img.Image applyToImage(img.Image image, AppSettingsState settings) {
    if (!settings.enableGlobalWatermark) return image;

    final text =
        settings.watermarkText.isEmpty ? '© PixelTools' : settings.watermarkText;
    final colorHex = settings.watermarkColorHex;
    final opacity = settings.watermarkOpacity.clamp(0.1, 1.0);
    final posIndex = settings.watermarkPositionIndex;

    final r = (colorHex >> 16) & 0xFF;
    final g = (colorHex >> 8) & 0xFF;
    final b = colorHex & 0xFF;
    final a = (opacity * 255).round().clamp(0, 255);

    // Pick font based on image dimensions
    final font = (image.width > 1600 || image.height > 1600)
        ? img.arial48
        : ((image.width > 800 || image.height > 800) ? img.arial24 : img.arial14);

    final charWidth = font == img.arial48 ? 28 : (font == img.arial24 ? 14 : 8);
    final charHeight = font == img.arial48 ? 48 : (font == img.arial24 ? 24 : 14);

    final textWidth = text.length * charWidth;
    final textHeight = charHeight;

    const margin = 20;
    int x;
    int y;

    switch (posIndex) {
      case 0: // Top-Left
        x = margin;
        y = margin;
        break;
      case 1: // Top-Right
        x = image.width - textWidth - margin;
        y = margin;
        break;
      case 2: // Center
        x = (image.width - textWidth) ~/ 2;
        y = (image.height - textHeight) ~/ 2;
        break;
      case 3: // Bottom-Left
        x = margin;
        y = image.height - textHeight - margin;
        break;
      case 4: // Bottom-Right
      default:
        x = image.width - textWidth - margin;
        y = image.height - textHeight - margin;
        break;
    }

    x = x.clamp(0, (image.width - textWidth).clamp(0, image.width));
    y = y.clamp(0, (image.height - textHeight).clamp(0, image.height));

    img.drawString(
      image,
      text,
      font: font,
      x: x,
      y: y,
      color: img.ColorRgba8(r, g, b, a),
    );

    return image;
  }
}
