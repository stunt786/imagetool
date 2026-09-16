import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

import '../../core/settings/app_settings.dart';

/// Helper service for drawing global watermarks on image bytes, decoded images,
/// and PDF documents.
class WatermarkHelper {
  WatermarkHelper._();

  static Uint8List? _cachedIconBytes;
  static img.Image? _cachedIconImage;

  static Uint8List? get cachedIconBytes => _cachedIconBytes;

  /// Loads `assets/icons/icon.png` into memory and decodes it once.
  static Future<Uint8List> loadIconBytes() async {
    if (_cachedIconBytes != null && _cachedIconBytes!.isNotEmpty) {
      return _cachedIconBytes!;
    }
    try {
      final data = await rootBundle.load('assets/icons/icon.png');
      _cachedIconBytes = data.buffer.asUint8List();
      _cachedIconImage = img.decodePng(_cachedIconBytes!);
      return _cachedIconBytes!;
    } catch (_) {
      try {
        final file = File('assets/icons/icon.png');
        if (file.existsSync()) {
          _cachedIconBytes = file.readAsBytesSync();
          _cachedIconImage = img.decodePng(_cachedIconBytes!);
          return _cachedIconBytes!;
        }
      } catch (_) {}
    }
    return Uint8List(0);
  }

  /// Sets or injects icon bytes (e.g. within an isolate).
  static void setIconBytes(Uint8List bytes) {
    _cachedIconBytes = bytes;
    if (bytes.isNotEmpty) {
      try {
        _cachedIconImage = img.decodePng(bytes);
      } catch (_) {}
    }
  }

  static void _ensureIconDecodedSync() {
    if (_cachedIconImage != null) return;
    if (_cachedIconBytes != null && _cachedIconBytes!.isNotEmpty) {
      try {
        _cachedIconImage = img.decodePng(_cachedIconBytes!);
        return;
      } catch (_) {}
    }
    try {
      final file = File('assets/icons/icon.png');
      if (file.existsSync()) {
        _cachedIconBytes = file.readAsBytesSync();
        _cachedIconImage = img.decodePng(_cachedIconBytes!);
      }
    } catch (_) {}
  }

  /// Applies global watermark to [imageBytes] if enabled in [settings].
  /// Returns modified image bytes or original [imageBytes] if disabled.
  static Uint8List applyGlobalWatermarkIfNeeded(
    Uint8List imageBytes,
    AppSettingsState settings, {
    Uint8List? iconBytes,
    bool? asRightVerticalSidebar,
  }) {
    if (!settings.enableGlobalWatermark || imageBytes.isEmpty) {
      return imageBytes;
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;

    final watermarked = applyToImage(
      decoded,
      settings,
      iconBytes: iconBytes,
      asRightVerticalSidebar: asRightVerticalSidebar,
    );

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

  /// Stretches watermark onto an [image] using either `icon.png` from assets
  /// or diamond fallback, plus [settings.watermarkText].
  /// If [asRightVerticalSidebar] is true (or null and [settings.useImageVerticalSidebar] is true),
  /// applies a subtle vertical sidebar along the right edge with low opacity.
  static img.Image applyToImage(
    img.Image image,
    AppSettingsState settings, {
    Uint8List? iconBytes,
    bool? asRightVerticalSidebar,
  }) {
    if (!settings.enableGlobalWatermark) return image;

    final useSidebar = asRightVerticalSidebar ?? settings.useImageVerticalSidebar;
    if (useSidebar) {
      return applyRightVerticalSidebar(image, settings, iconBytes: iconBytes);
    }

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

    if (iconBytes != null && iconBytes.isNotEmpty) {
      setIconBytes(iconBytes);
    } else {
      _ensureIconDecodedSync();
    }

    final useLogo = settings.useWatermarkLogo;
    img.Image? scaledIcon;
    int iconDim = 0;
    if (useLogo && _cachedIconImage != null) {
      iconDim = charHeight;
      scaledIcon = img.copyResize(
        _cachedIconImage!,
        width: iconDim,
        height: iconDim,
        interpolation: img.Interpolation.linear,
      );
    } else if (useLogo) {
      iconDim = charHeight; // fallback diamond
    }

    final spacing = (charWidth * 0.45).round();
    final totalWidth = (iconDim > 0 ? iconDim + spacing : 0) + text.length * charWidth;

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

    x = x.clamp(0, math.max(0, image.width - totalWidth));
    y = y.clamp(0, math.max(0, image.height - charHeight));

    int curX = x;
    if (scaledIcon != null) {
      img.compositeImage(
        image,
        scaledIcon,
        dstX: curX,
        dstY: y + (charHeight - scaledIcon.height) ~/ 2,
      );
      curX += iconDim + spacing;
    } else if (useLogo) {
      // Fallback diamond if icon was not decodable
      final diamondSize = charHeight;
      final dcx = curX + diamondSize ~/ 2;
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
      curX += diamondSize + spacing;
    }

    final textColor = img.ColorRgba8(r, g, b, a);
    img.drawString(
      image,
      text,
      font: font,
      x: curX,
      y: y,
      color: textColor,
    );

    return image;
  }

  /// Applies a subtle, vertical sidebar watermark along the right edge of an image.
  /// Uses low opacity, icon.png (or logo fallback), and watermark text flowing vertically.
  static img.Image applyRightVerticalSidebar(
    img.Image image,
    AppSettingsState settings, {
    Uint8List? iconBytes,
  }) {
    if (!settings.enableGlobalWatermark) return image;

    final text = settings.watermarkText.isEmpty ? 'PixelTools' : settings.watermarkText;
    final colorHex = settings.watermarkColorHex;

    // Subtle low opacity for photo exports
    final contentOpacity = (settings.watermarkOpacity * 0.50).clamp(0.20, 0.40);

    final r = (colorHex >> 16) & 0xFF;
    final g = (colorHex >> 8) & 0xFF;
    final b = colorHex & 0xFF;
    final textAlpha = (contentOpacity * 255).round().clamp(0, 255);

    final minDimension = math.min(image.width, image.height);
    final font = minDimension >= 1800
        ? img.arial48
        : (minDimension >= 700 ? img.arial24 : img.arial14);

    final charWidth = font == img.arial48 ? 28 : (font == img.arial24 ? 14 : 8);
    final charHeight = font == img.arial48 ? 48 : (font == img.arial24 ? 24 : 14);

    if (iconBytes != null && iconBytes.isNotEmpty) {
      setIconBytes(iconBytes);
    } else {
      _ensureIconDecodedSync();
    }

    final useLogo = settings.useWatermarkLogo;
    img.Image? scaledIcon;
    int iconDim = 0;
    if (useLogo && _cachedIconImage != null) {
      iconDim = charHeight;
      scaledIcon = img.copyResize(
        _cachedIconImage!,
        width: iconDim,
        height: iconDim,
        interpolation: img.Interpolation.linear,
      );
    } else if (useLogo) {
      iconDim = charHeight;
    }

    final padX = (charWidth * 0.4).round();
    final padY = (charHeight * 0.2).round();
    final spacing = (charWidth * 0.45).round();
    final contentWidth = (iconDim > 0 ? iconDim + spacing : 0) + text.length * charWidth;
    final stripWidth = contentWidth + padX * 2;
    final stripHeight = charHeight + padY * 2;

    // Create transparent horizontal strip canvas (no background color)
    final strip = img.Image(width: stripWidth, height: stripHeight, numChannels: 4);
    strip.clear(img.ColorRgba8(0, 0, 0, 0));

    int drawX = padX;
    final drawY = padY;

    if (scaledIcon != null) {
      // Multiply icon alpha by contentOpacity for soft, low opacity look
      for (final p in scaledIcon) {
        p.a = (p.a * contentOpacity).round().clamp(0, 255);
      }
      img.compositeImage(
        strip,
        scaledIcon,
        dstX: drawX,
        dstY: drawY + (charHeight - scaledIcon.height) ~/ 2,
      );
      drawX += iconDim + spacing;
    } else if (useLogo) {
      final diamondSize = charHeight;
      final dcx = drawX + diamondSize ~/ 2;
      final dcy = drawY + charHeight ~/ 2;
      final dr = diamondSize ~/ 2 - 1;
      final textColor = img.ColorRgba8(r, g, b, textAlpha);

      for (int dy = -dr; dy <= dr; dy++) {
        final rowWidth = dr - dy.abs();
        for (int dx = -rowWidth; dx <= rowWidth; dx++) {
          final px = dcx + dx;
          final py = dcy + dy;
          if (px >= 0 && px < strip.width && py >= 0 && py < strip.height) {
            strip.setPixel(px, py, textColor);
          }
        }
      }
      drawX += diamondSize + spacing;
    }

    final textColor = img.ColorRgba8(r, g, b, textAlpha);
    img.drawString(
      strip,
      text,
      font: font,
      x: drawX,
      y: drawY,
      color: textColor,
    );

    // Rotate horizontal strip 90 degrees clockwise to become a vertical strip
    // (with icon at top and text reading downward)
    img.Image verticalStrip = img.copyRotate(strip, angle: 90);

    // Clamp / scale if verticalStrip height exceeds image height
    if (verticalStrip.height > image.height && image.height > 10) {
      final scale = (image.height - 8) / verticalStrip.height;
      if (scale > 0) {
        verticalStrip = img.copyResize(
          verticalStrip,
          width: math.max(1, (verticalStrip.width * scale).round()),
          height: math.max(1, (verticalStrip.height * scale).round()),
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Position along right edge, vertically centered
    final margin = (minDimension * 0.02).clamp(8.0, 32.0).round();
    final int dstX = (image.width - verticalStrip.width - margin)
        .clamp(0, math.max(0, image.width - verticalStrip.width))
        .toInt();
    final int dstY = ((image.height - verticalStrip.height) ~/ 2)
        .clamp(0, math.max(0, image.height - verticalStrip.height))
        .toInt();

    // Alpha blend vertical strip onto the image using Porter-Duff Over
    for (int sy = 0; sy < verticalStrip.height; sy++) {
      final dy = dstY + sy;
      if (dy < 0 || dy >= image.height) continue;
      for (int sx = 0; sx < verticalStrip.width; sx++) {
        final dx = dstX + sx;
        if (dx < 0 || dx >= image.width) continue;
        final srcPixel = verticalStrip.getPixel(sx, sy);
        if (srcPixel.a == 0) continue;

        final dstPixel = image.getPixel(dx, dy);
        final sa = srcPixel.a / 255.0;
        final da = dstPixel.a / 255.0;
        final outA = sa + da * (1.0 - sa);
        if (outA > 0) {
          final outR = ((srcPixel.r * sa + dstPixel.r * da * (1.0 - sa)) / outA).round();
          final outG = ((srcPixel.g * sa + dstPixel.g * da * (1.0 - sa)) / outA).round();
          final outB = ((srcPixel.b * sa + dstPixel.b * da * (1.0 - sa)) / outA).round();
          image.setPixel(
            dx,
            dy,
            img.ColorRgba8(outR, outG, outB, (outA * 255).round()),
          );
        }
      }
    }

    return image;
  }

  /// Builds a PDF watermark widget for `package:pdf/widgets.dart` documents.
  static pw.Widget buildPdfWatermarkWidget({
    required Uint8List? iconBytes,
    required String text,
    required int colorHex,
    required double opacity,
    required int positionIndex,
    bool useAppLogo = true,
  }) {
    final safeOpacity = opacity.clamp(0.1, 1.0);
    final r = ((colorHex >> 16) & 0xFF) / 255.0;
    final g = ((colorHex >> 8) & 0xFF) / 255.0;
    final b = (colorHex & 0xFF) / 255.0;
    final textColor = pdf.PdfColor(r, g, b, safeOpacity);

    pw.Alignment alignment;
    switch (positionIndex) {
      case 0:
        alignment = pw.Alignment.topLeft;
        break;
      case 1:
        alignment = pw.Alignment.topRight;
        break;
      case 2:
        alignment = pw.Alignment.center;
        break;
      case 3:
        alignment = pw.Alignment.bottomLeft;
        break;
      case 4:
      default:
        alignment = pw.Alignment.bottomRight;
        break;
    }

    final effectiveBytes = iconBytes ?? _cachedIconBytes;
    final hasIcon = useAppLogo && effectiveBytes != null && effectiveBytes.isNotEmpty;

    return pw.Align(
      alignment: alignment,
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(16),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
              if (hasIcon) ...[
                pw.ClipRRect(
                  horizontalRadius: 3,
                  verticalRadius: 3,
                  child: pw.Image(
                    pw.MemoryImage(effectiveBytes),
                    width: 14,
                    height: 14,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(width: 5),
              ],
              if (text.isNotEmpty)
                pw.Text(
                  text,
                  style: pw.TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
    );
  }
}
