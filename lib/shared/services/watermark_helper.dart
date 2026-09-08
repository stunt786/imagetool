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

  static img.Image applyToImage(img.Image image, AppSettingsState settings) {
    if (!settings.enableGlobalWatermark) return image;

    final text = settings.watermarkText.isEmpty ? 'PixelTools' : settings.watermarkText;
    final colorHex = settings.watermarkColorHex;
    final opacity = settings.watermarkOpacity.clamp(0.1, 1.0);
    final posIndex = settings.watermarkPositionIndex;

    final r = (colorHex >> 16) & 0xFF;
    final g = (colorHex >> 8) & 0xFF;
    final b = colorHex & 0xFF;
    final a = (opacity * 255).round().clamp(0, 255);

    final font = (image.width > 1600 || image.height > 1600)
        ? img.arial48
        : ((image.width > 800 || image.height > 800)
            ? img.arial24
            : img.arial14);

    final charWidth = font == img.arial48 ? 28 : (font == img.arial24 ? 14 : 8);
    final charHeight = font == img.arial48 ? 48 : (font == img.arial24 ? 24 : 14);

    final diamondSize = charHeight;
    final spacing = (charWidth * 0.4).round();
    final totalWidth = diamondSize + spacing + text.length * charWidth;

    const margin = 20;
    int x;
    int y;

    switch (posIndex) {
      case 0:
        x = margin;
        y = margin;
        break;
      case 1:
        x = image.width - totalWidth - margin;
        y = margin;
        break;
      case 2:
        x = (image.width - totalWidth) ~/ 2;
        y = (image.height - charHeight) ~/ 2;
        break;
      case 3:
        x = margin;
        y = image.height - charHeight - margin;
        break;
      case 4:
      default:
        x = image.width - totalWidth - margin;
        y = image.height - charHeight - margin;
        break;
    }

    x = x.clamp(0, (image.width - totalWidth).clamp(0, image.width));
    y = y.clamp(0, (image.height - charHeight).clamp(0, image.height));

    final bgColor = img.ColorRgba8(0, 0, 0, (a * 0.35).round().clamp(0, 255));
    final bgPadX = (charWidth * 0.6).round();
    final bgPadY = (charHeight * 0.3).round();
    final bgLeft = (x - bgPadX).clamp(0, image.width);
    final bgTop = (y - bgPadY).clamp(0, image.height);
    final bgRight = (x + totalWidth + bgPadX).clamp(0, image.width);
    final bgBottom = (y + charHeight + bgPadY).clamp(0, image.height);

    for (int py = bgTop; py < bgBottom; py++) {
      for (int px = bgLeft; px < bgRight; px++) {
        final existing = image.getPixel(px, py);
        final srcA = existing.a / 255.0;
        final dstA = bgColor.a / 255.0;
        final outA = dstA + srcA * (1.0 - dstA);
        if (outA > 0) {
          final outR = ((bgColor.r * dstA + existing.r * srcA * (1.0 - dstA)) / outA).round();
          final outG = ((bgColor.g * dstA + existing.g * srcA * (1.0 - dstA)) / outA).round();
          final outB = ((bgColor.b * dstA + existing.b * srcA * (1.0 - dstA)) / outA).round();
          image.setPixel(px, py, img.ColorRgba8(outR, outG, outB, (outA * 255).round()));
        }
      }
    }

    final dcx = x + diamondSize ~/ 2;
    final dcy = y + charHeight ~/ 2;
    final dr = diamondSize ~/ 2 - 1;
    final textColor = img.ColorRgba8(r, g, b, a);

    for (int dy = -dr; dy <= dr; dy++) {
      final rowWidth = dr - dy.abs();
      for (int dx = -rowWidth; dx <= rowWidth; dx++) {
        final px = dcx + dx;
        final py = dcy + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          final existing = image.getPixel(px, py);
          final srcA = textColor.a / 255.0;
          final dstA = existing.a / 255.0;
          final outA = srcA + dstA * (1.0 - srcA);
          if (outA > 0) {
            final outR = ((textColor.r * srcA + existing.r * dstA * (1.0 - srcA)) / outA).round();
            final outG = ((textColor.g * srcA + existing.g * dstA * (1.0 - srcA)) / outA).round();
            final outB = ((textColor.b * srcA + existing.b * dstA * (1.0 - srcA)) / outA).round();
            image.setPixel(px, py, img.ColorRgba8(outR, outG, outB, (outA * 255).round()));
          }
        }
      }
    }

    img.drawString(
      image,
      text,
      font: font,
      x: x + diamondSize + spacing,
      y: y,
      color: textColor,
    );

    return image;
  }
}
