import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

/// Professional document enhancement service providing:
/// 1. Auto-fitting scan to full paper bounds (removes background/desk borders)
/// 2. Auto-flattening bended/curved paper (dewarping page curls)
/// 3. Auto-adjusting brightness & contrast for dark/underexposed images
/// 4. Autocorrecting shadows from antilights, harsh overhead lights, and hands
/// Result of a smart enhancement pass with the stages that actually ran.
class SmartEnhanceResult {
  const SmartEnhanceResult({required this.bytes, required this.stages});

  final Uint8List bytes;
  final List<String> stages;
}

class DocumentEnhancementService {
  /// Auto-fits the document to the full paper size by cropping out surrounding table/margins.
  static Future<Uint8List?> autoFitToPaper(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final fitted = internalAutoFitPaper(image);
      return Uint8List.fromList(img.encodeJpg(fitted, quality: 95));
    });
  }

  /// Auto-flattens the scanned image if the paper is bended or curved.
  static Future<Uint8List?> autoFlattenBendedPaper(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final flattened = internalAutoFlattenPaper(image);
      return Uint8List.fromList(img.encodeJpg(flattened, quality: 95));
    });
  }

  /// Automatically adjusts brightness and contrast for dark or underexposed scans.
  static Future<Uint8List?> autoAdjustDarkImage(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final adjusted = internalAutoAdjustDarkImage(image);
      return Uint8List.fromList(img.encodeJpg(adjusted, quality: 95));
    });
  }

  /// Autocorrects uneven shadows, antilight gradients, and camera/hand shadows.
  static Future<Uint8List?> autocorrectAntiLightShadows(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final corrected = internalAutocorrectAntiLightShadows(image);
      return Uint8List.fromList(img.encodeJpg(corrected, quality: 95));
    });
  }

  /// Smart Clean filter: cleans up unwanted objects (fingers holding paper,
  /// housefly, dirt/spots, foreign objects placed over document) and levels
  /// lighting/background WITHOUT warping or distorting geometry.
  static Future<SmartEnhanceResult?> smartScanEnhanceDetailed(
    Uint8List bytes,
  ) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final stages = <String>[];
      final processed = internalSmartClean(image, stagesOut: stages);

      return SmartEnhanceResult(
        bytes: Uint8List.fromList(img.encodeJpg(processed, quality: 95)),
        stages: stages,
      );
    });
  }

  /// All-in-one smart scan clean:
  /// Cleans unwanted objects and normalizes background without warping.
  static Future<Uint8List?> smartScanEnhance(Uint8List bytes) async {
    final result = await smartScanEnhanceDetailed(bytes);
    return result?.bytes;
  }

  /// Auto flatten: straightens paper orientation/quad and makes paper smooth,
  /// clearing raised and down parts in pages (creases, curls, gutter folds).
  static Future<Uint8List?> flattenDocument(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final flattened = internalAutoFlattenSmooth(image);
      return Uint8List.fromList(img.encodeJpg(flattened, quality: 95));
    });
  }

  /// Detects the 4 paper corners in normalized (0.0 - 1.0) coordinates.
  static Future<List<Offset>> detectDocumentCorners(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) {
        return const [
          Offset(0.05, 0.05),
          Offset(0.95, 0.05),
          Offset(0.95, 0.95),
          Offset(0.05, 0.95),
        ];
      }
      return internalDetectPaperCorners(image);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal Pure Image Processing Implementations (run inside background Isolates)
  // ──────────────────────────────────────────────────────────────────────────

  /// Detects quadrilateral paper corners in normalized coordinates (0.0 to 1.0)
  static List<Offset> internalDetectPaperCorners(img.Image image) {
    final w = image.width;
    final h = image.height;

    const maxDim = 320;
    final scale = math.min(1.0, maxDim / math.max(w, h));
    final smallW = (w * scale).round().clamp(10, w);
    final smallH = (h * scale).round().clamp(10, h);
    final small = img.copyResize(image, width: smallW, height: smallH);
    final gray = img.grayscale(small);
    final edges = img.sobel(gray);

    var minX = 0;
    var maxX = smallW - 1;
    var minY = 0;
    var maxY = smallH - 1;

    const threshold = 35;

    // Left border
    for (var x = 0; x < smallW ~/ 3; x++) {
      var count = 0;
      for (var y = smallH ~/ 4; y < 3 * smallH ~/ 4; y++) {
        if (edges.getPixel(x, y).r > threshold) count++;
      }
      if (count > smallH * 0.15) {
        minX = x;
        break;
      }
    }

    // Right border
    for (var x = smallW - 1; x > 2 * smallW ~/ 3; x--) {
      var count = 0;
      for (var y = smallH ~/ 4; y < 3 * smallH ~/ 4; y++) {
        if (edges.getPixel(x, y).r > threshold) count++;
      }
      if (count > smallH * 0.15) {
        maxX = x;
        break;
      }
    }

    // Top border
    for (var y = 0; y < smallH ~/ 3; y++) {
      var count = 0;
      for (var x = smallW ~/ 4; x < 3 * smallW ~/ 4; x++) {
        if (edges.getPixel(x, y).r > threshold) count++;
      }
      if (count > smallW * 0.15) {
        minY = y;
        break;
      }
    }

    // Bottom border
    for (var y = smallH - 1; y > 2 * smallH ~/ 3; y--) {
      var count = 0;
      for (var x = smallW ~/ 4; x < 3 * smallW ~/ 4; x++) {
        if (edges.getPixel(x, y).r > threshold) count++;
      }
      if (count > smallW * 0.15) {
        maxY = y;
        break;
      }
    }

    final normLeft = (minX / smallW).clamp(0.0, 0.35);
    final normRight = (maxX / smallW).clamp(0.65, 1.0);
    final normTop = (minY / smallH).clamp(0.0, 0.35);
    final normBottom = (maxY / smallH).clamp(0.65, 1.0);

    return [
      Offset(normLeft, normTop),
      Offset(normRight, normTop),
      Offset(normRight, normBottom),
      Offset(normLeft, normBottom),
    ];
  }

  /// Automatically fits the paper to the full image frame.
  static img.Image internalAutoFitPaper(img.Image src) {
    final corners = internalDetectPaperCorners(src);
    final minX = (corners[0].dx * src.width).round();
    final minY = (corners[0].dy * src.height).round();
    final maxX = (corners[2].dx * src.width).round();
    final maxY = (corners[2].dy * src.height).round();

    final cropW = (maxX - minX).clamp(1, src.width);
    final cropH = (maxY - minY).clamp(1, src.height);

    // If already covering > 92% of frame, keep intact
    if (cropW > src.width * 0.92 && cropH > src.height * 0.92) {
      return src;
    }

    if (cropW > 80 && cropH > 80) {
      return img.copyCrop(src,
          x: minX.clamp(0, src.width - cropW),
          y: minY.clamp(0, src.height - cropH),
          width: cropW,
          height: cropH);
    }

    return src;
  }

  /// Cleans up unwanted objects (housefly, dirt, objects placed over document,
  /// fingers holding paper) and normalizes paper background WITHOUT WARPING.
  static img.Image internalSmartClean(
    img.Image src, {
    List<String>? stagesOut,
  }) {
    img.Image result = src.clone();
    final w = result.width;
    final h = result.height;
    if (w < 10 || h < 10) return result;

    // 1. Remove fingers holding paper near edges/margins
    final fingersCleaned = _cleanFingerIntrusions(result);
    if (fingersCleaned) {
      stagesOut?.add('Fingers removed');
    }

    // 2. Remove unwanted objects like housefly, dirt, spots, foreign objects placed over paper
    final objectsCleaned = _cleanUnwantedObjectsAndDirt(result);
    if (objectsCleaned) {
      stagesOut?.add('Dirt & objects cleaned');
    }

    // 3. Clean background & remove harsh antilight shadows without warping
    if (internalHasUnevenIllumination(result)) {
      result = internalAutocorrectAntiLightShadows(result);
      stagesOut?.add('Shadows removed');
    } else {
      result = _levelPaperBackground(result);
      stagesOut?.add('Background cleaned');
    }

    // 4. Adjust brightness if dark/underexposed
    final brightened = internalAutoAdjustDarkImage(result);
    if (!identical(brightened, result)) {
      stagesOut?.add('Brightness');
      result = brightened;
    }

    return result;
  }

  /// Detects and cleans fingers holding down the document borders.
  static bool _cleanFingerIntrusions(img.Image image) {
    final w = image.width;
    final h = image.height;
    final scale = math.min(1.0, 360.0 / math.max(w, h));
    final sw = (w * scale).round().clamp(10, w);
    final sh = (h * scale).round().clamp(10, h);
    final small = img.copyResize(image, width: sw, height: sh);

    var paperR = 0, paperG = 0, paperB = 0;
    var paperSamples = 0;
    for (var y = sh ~/ 4; y < sh * 3 ~/ 4; y += 3) {
      for (var x = sw ~/ 4; x < sw * 3 ~/ 4; x += 3) {
        final p = small.getPixel(x, y);
        paperR += p.r.toInt();
        paperG += p.g.toInt();
        paperB += p.b.toInt();
        paperSamples++;
      }
    }
    if (paperSamples == 0) return false;
    final avgPaperR = paperR ~/ paperSamples;
    final avgPaperG = paperG ~/ paperSamples;
    final avgPaperB = paperB ~/ paperSamples;
    final paperLum = 0.299 * avgPaperR + 0.587 * avgPaperG + 0.114 * avgPaperB;

    final marginX = (sw * 0.18).round();
    final marginY = (sh * 0.18).round();

    final mask = List<int>.filled(sw * sh, 0);
    for (var y = 0; y < sh; y++) {
      final isNearEdgeY = y < marginY || y > sh - marginY;
      for (var x = 0; x < sw; x++) {
        final isNearEdgeX = x < marginX || x > sw - marginX;
        if (!isNearEdgeX && !isNearEdgeY) continue;

        final p = small.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;

        // Skin-tone detection in RGB color space
        final isSkin = r > 65 &&
            g > 30 &&
            b > 15 &&
            r > g &&
            g >= (b * 0.75) &&
            (r - g) < 130 &&
            (r - b) < 160 &&
            (r - g) >= 8;

        // Or dark finger silhouette touching outer border
        final isDarkFinger = (x <= 3 || x >= sw - 4 || y <= 3 || y >= sh - 4) &&
            lum < paperLum - 50 &&
            lum < 130;

        if (isSkin || isDarkFinger) {
          mask[y * sw + x] = 1;
        }
      }
    }

    final visited = List<int>.filled(sw * sh, 0);
    var modifiedAny = false;

    for (var i = 0; i < sw * sh; i++) {
      if (mask[i] != 1 || visited[i] == 1) continue;
      final stack = <int>[i];
      visited[i] = 1;
      final comp = <int>[];
      var touchesBorder = false;
      var minX = sw, maxX = 0, minY = sh, maxY = 0;

      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        comp.add(cur);
        final cx = cur % sw;
        final cy = cur ~/ sw;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        if (cx == 0 || cy == 0 || cx == sw - 1 || cy == sh - 1) {
          touchesBorder = true;
        }

        for (final offset in [-1, 1, -sw, sw]) {
          final next = cur + offset;
          if (next >= 0 && next < sw * sh) {
            if ((offset == -1 && cx == 0) || (offset == 1 && cx == sw - 1)) {
              continue;
            }
            if (mask[next] == 1 && visited[next] == 0) {
              visited[next] = 1;
              stack.add(next);
            }
          }
        }
      }

      final compWidth = maxX - minX + 1;
      final compHeight = maxY - minY + 1;
      final compArea = comp.length;
      final maxArea = (sw * sh * 0.30).round();

      if (touchesBorder &&
          compArea >= 25 &&
          compArea < maxArea &&
          compWidth >= 8 &&
          compHeight >= 8) {
        final fullMinX = (minX / scale).floor().clamp(0, w - 1);
        final fullMaxX = (maxX / scale).ceil().clamp(0, w - 1);
        final fullMinY = (minY / scale).floor().clamp(0, h - 1);
        final fullMaxY = (maxY / scale).ceil().clamp(0, h - 1);

        final bg = _sampleCleanBackgroundNear(
            image, fullMinX, fullMinY, fullMaxX, fullMaxY, avgPaperR, avgPaperG, avgPaperB);

        for (final pixelIndex in comp) {
          final cx = pixelIndex % sw;
          final cy = pixelIndex ~/ sw;
          final pxStart = (cx / scale).floor().clamp(0, w - 1);
          final pxEnd = ((cx + 1) / scale).ceil().clamp(0, w);
          final pyStart = (cy / scale).floor().clamp(0, h - 1);
          final pyEnd = ((cy + 1) / scale).ceil().clamp(0, h);

          for (var py = pyStart; py < pyEnd; py++) {
            for (var px = pxStart; px < pxEnd; px++) {
              image.setPixelRgb(px, py, bg[0], bg[1], bg[2]);
              modifiedAny = true;
            }
          }
        }
      }
    }

    return modifiedAny;
  }

  /// Removes isolated unwanted objects (housefly, dirt, spots, foreign objects placed over paper).
  static bool _cleanUnwantedObjectsAndDirt(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 20 || h < 20) return false;

    final scale = math.min(1.0, 480.0 / math.max(w, h));
    final sw = (w * scale).round().clamp(10, w);
    final sh = (h * scale).round().clamp(10, h);
    final small = img.copyResize(image, width: sw, height: sh);
    final gray = img.grayscale(small);

    const gridCols = 16;
    const gridRows = 16;
    final bgGrid = List<double>.filled(gridCols * gridRows, 240.0);
    final cellW = sw / gridCols;
    final cellH = sh / gridRows;

    for (var gy = 0; gy < gridRows; gy++) {
      for (var gx = 0; gx < gridCols; gx++) {
        final x0 = (gx * cellW).floor().clamp(0, sw - 1);
        final x1 = ((gx + 1) * cellW).floor().clamp(0, sw);
        final y0 = (gy * cellH).floor().clamp(0, sh - 1);
        final y1 = ((gy + 1) * cellH).floor().clamp(0, sh);
        final vals = <int>[];
        for (var y = y0; y < y1; y += 2) {
          for (var x = x0; x < x1; x += 2) {
            vals.add(gray.getPixel(x, y).r.toInt());
          }
        }
        if (vals.isNotEmpty) {
          vals.sort();
          bgGrid[gy * gridCols + gx] = vals[(vals.length * 0.85).floor()].toDouble();
        }
      }
    }

    double sampleBgLum(int x, int y) {
      final gx = ((x / sw) * gridCols - 0.5).clamp(0.0, gridCols - 1.001);
      final gy = ((y / sh) * gridRows - 0.5).clamp(0.0, gridRows - 1.001);
      final x0 = gx.floor(), y0 = gy.floor();
      final x1 = (x0 + 1).clamp(0, gridCols - 1);
      final y1 = (y0 + 1).clamp(0, gridRows - 1);
      final fx = gx - x0, fy = gy - y0;
      final v00 = bgGrid[y0 * gridCols + x0];
      final v10 = bgGrid[y0 * gridCols + x1];
      final v01 = bgGrid[y1 * gridCols + x0];
      final v11 = bgGrid[y1 * gridCols + x1];
      return (v00 * (1 - fx) + v10 * fx) * (1 - fy) +
          (v01 * (1 - fx) + v11 * fx) * fy;
    }

    final darkMask = List<int>.filled(sw * sh, 0);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final lum = gray.getPixel(x, y).r.toInt();
        final bg = sampleBgLum(x, y);
        if (bg - lum > 35) {
          darkMask[y * sw + x] = 1;
        }
      }
    }

    final visited = List<int>.filled(sw * sh, 0);
    var removedAny = false;
    final marginX = (sw * 0.08).round();
    final marginY = (sh * 0.08).round();

    for (var i = 0; i < sw * sh; i++) {
      if (darkMask[i] != 1 || visited[i] == 1) continue;
      final stack = <int>[i];
      visited[i] = 1;
      final comp = <int>[];
      var minX = sw, maxX = 0, minY = sh, maxY = 0;

      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        comp.add(cur);
        final cx = cur % sw;
        final cy = cur ~/ sw;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;

        for (final offset in [-1, 1, -sw, sw]) {
          final next = cur + offset;
          if (next >= 0 && next < sw * sh) {
            if ((offset == -1 && cx == 0) || (offset == 1 && cx == sw - 1)) {
              continue;
            }
            if (darkMask[next] == 1 && visited[next] == 0) {
              visited[next] = 1;
              stack.add(next);
            }
          }
        }
      }

      final blobWidth = maxX - minX + 1;
      final blobHeight = maxY - minY + 1;
      final blobArea = comp.length;

      // Count external dark pixels within a surrounding radius
      var surroundingDark = 0;
      const pad = 8;
      final pMinX = math.max(0, minX - pad);
      final pMaxX = math.min(sw - 1, maxX + pad);
      final pMinY = math.max(0, minY - pad);
      final pMaxY = math.min(sh - 1, maxY + pad);

      for (var y = pMinY; y <= pMaxY; y++) {
        for (var x = pMinX; x <= pMaxX; x++) {
          if (x >= minX && x <= maxX && y >= minY && y <= maxY) continue;
          if (darkMask[y * sw + x] == 1) surroundingDark++;
        }
      }

      // An isolated housefly, bug, dirt speck, crumb, or blemish:
      // Has almost no other dark pixels in its surrounding neighborhood (isolated on paper)
      // and has small-to-medium compact size (not a large photo/diagram).
      final isHouseflyOrDirt = (surroundingDark <= 4) &&
          blobArea >= 2 &&
          blobArea <= 600 &&
          blobWidth <= 60 &&
          blobHeight <= 60;

      // Foreign object in margins (clips, staples, stamps, smudges, stray marks):
      final isInMargin = minX < marginX ||
          maxX > sw - marginX ||
          minY < marginY ||
          maxY > sh - marginY;
      final isMarginObject = isInMargin &&
          (surroundingDark <= 12) &&
          blobArea <= 2000;

      if (isHouseflyOrDirt || isMarginObject) {
        final fullMinX = (minX / scale).floor().clamp(0, w - 1);
        final fullMaxX = (maxX / scale).ceil().clamp(0, w - 1);
        final fullMinY = (minY / scale).floor().clamp(0, h - 1);
        final fullMaxY = (maxY / scale).ceil().clamp(0, h - 1);

        final bg = _sampleCleanBackgroundNear(
            image, fullMinX, fullMinY, fullMaxX, fullMaxY, 245, 245, 245);

        for (final pixelIndex in comp) {
          final cx = pixelIndex % sw;
          final cy = pixelIndex ~/ sw;
          final pxStart = (cx / scale).floor().clamp(0, w - 1);
          final pxEnd = ((cx + 1) / scale).ceil().clamp(0, w);
          final pyStart = (cy / scale).floor().clamp(0, h - 1);
          final pyEnd = ((cy + 1) / scale).ceil().clamp(0, h);

          for (var py = pyStart; py < pyEnd; py++) {
            for (var px = pxStart; px < pxEnd; px++) {
              image.setPixelRgb(px, py, bg[0], bg[1], bg[2]);
              removedAny = true;
            }
          }
        }
      }
    }

    return removedAny;
  }

  static List<int> _sampleCleanBackgroundNear(
    img.Image image,
    int minX,
    int minY,
    int maxX,
    int maxY,
    int fallbackR,
    int fallbackG,
    int fallbackB,
  ) {
    var sumR = 0, sumG = 0, sumB = 0, count = 0;
    const ringPad = 12;
    final rMinX = math.max(0, minX - ringPad);
    final rMaxX = math.min(image.width - 1, maxX + ringPad);
    final rMinY = math.max(0, minY - ringPad);
    final rMaxY = math.min(image.height - 1, maxY + ringPad);

    for (var y = rMinY; y <= rMaxY; y += 2) {
      for (var x = rMinX; x <= rMaxX; x += 2) {
        if (x >= minX && x <= maxX && y >= minY && y <= maxY) continue;
        final p = image.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum > 140) {
          sumR += p.r.toInt();
          sumG += p.g.toInt();
          sumB += p.b.toInt();
          count++;
        }
      }
    }
    if (count > 0) {
      return [
        (sumR / count).round().clamp(0, 255),
        (sumG / count).round().clamp(0, 255),
        (sumB / count).round().clamp(0, 255),
      ];
    }
    return [fallbackR, fallbackG, fallbackB];
  }

  static img.Image _levelPaperBackground(img.Image src) {
    const bgDim = 48;
    final smallW = math.max(16, src.width ~/ bgDim);
    final smallH = math.max(16, src.height ~/ bgDim);
    final small = img.copyResize(src, width: smallW, height: smallH);

    final dilated = img.Image(width: smallW, height: smallH);
    const k = 2;
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        var maxR = 0, maxG = 0, maxB = 0;
        for (var dy = -k; dy <= k; dy++) {
          final ny = (y + dy).clamp(0, smallH - 1);
          for (var dx = -k; dx <= k; dx++) {
            final nx = (x + dx).clamp(0, smallW - 1);
            final p = small.getPixel(nx, ny);
            if (p.r > maxR) maxR = p.r.toInt();
            if (p.g > maxG) maxG = p.g.toInt();
            if (p.b > maxB) maxB = p.b.toInt();
          }
        }
        dilated.setPixelRgb(x, y, maxR, maxG, maxB);
      }
    }

    final blurred = img.gaussianBlur(dilated, radius: 4);
    final bgMap = img.copyResize(blurred, width: src.width, height: src.height);
    final result = src.clone();
    const targetBg = 248.0;

    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final bg = bgMap.getPixel(x, y);
        final bgLum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
        final pLum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;

        if (pLum > bgLum - 30) {
          final bgR = math.max(30.0, bg.r.toDouble());
          final bgG = math.max(30.0, bg.g.toDouble());
          final bgB = math.max(30.0, bg.b.toDouble());
          final nr = ((p.r / bgR) * targetBg).clamp(0.0, 255.0).toInt();
          final ng = ((p.g / bgG) * targetBg).clamp(0.0, 255.0).toInt();
          final nb = ((p.b / bgB) * targetBg).clamp(0.0, 255.0).toInt();
          result.setPixelRgb(x, y, nr, ng, nb);
        }
      }
    }
    return result;
  }

  /// Auto flatten: straightens paper orientation and makes paper smooth,
  /// clearing raised and down parts in pages (peaks, troughs, curls, crease shadows).
  static img.Image internalAutoFlattenSmooth(img.Image src) {
    // 1. Straighten perspective quad / deskew
    final straightened = internalFlattenStraighten(src);

    final w = straightened.width;
    final h = straightened.height;
    if (w < 40 || h < 40) return straightened;

    // 2. Curvature analysis: analyze raised and down parts across slices
    const numSlices = 28;
    final sliceWidth = w / numSlices;
    final detectedOffsets = List<double>.filled(numSlices, 0.0);

    for (var s = 0; s < numSlices; s++) {
      final startX = (s * sliceWidth).round().clamp(0, w - 1);
      final endX = ((s + 1) * sliceWidth).round().clamp(0, w - 1);

      var weightSum = 0.0;
      var yWeightedSum = 0.0;

      for (var y = 0; y < h; y++) {
        for (var x = startX; x < endX; x++) {
          final p = straightened.getPixel(x, y);
          final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          if (lum < 165) {
            final darkness = 165 - lum;
            weightSum += darkness;
            yWeightedSum += darkness * y;
          }
        }
      }

      if (weightSum > 30) {
        detectedOffsets[s] = yWeightedSum / weightSum;
      } else {
        detectedOffsets[s] = h / 2.0;
      }
    }

    final smoothedOffsets = List<double>.filled(numSlices, 0.0);
    for (var i = 0; i < numSlices; i++) {
      var weightedSum = 0.0;
      var weight = 0.0;
      for (var j = math.max(0, i - 3); j <= math.min(numSlices - 1, i + 3); j++) {
        final w = 4.0 - (i - j).abs();
        weightedSum += detectedOffsets[j] * w;
        weight += w;
      }
      smoothedOffsets[i] = weightedSum / weight;
    }

    final avgOffset = smoothedOffsets.reduce((a, b) => a + b) / numSlices;
    final relativeDips = smoothedOffsets.map((y) => y - avgOffset).toList();
    final maxDip = relativeDips.reduce(math.max);
    final minDip = relativeDips.reduce(math.min);
    final curveAmplitude = maxDip - minDip;

    img.Image dewarped = straightened;

    // Invert the curvature: pulling up down troughs and leveling raised parts
    if (curveAmplitude >= (h * 0.015) && curveAmplitude <= (h * 0.20)) {
      dewarped = img.Image(width: w, height: h);
      for (var x = 0; x < w; x++) {
        final slicePos = (x / w) * numSlices - 0.5;
        final s0 = slicePos.floor().clamp(0, numSlices - 1);
        final s1 = (s0 + 1).clamp(0, numSlices - 1);
        final t = (slicePos - s0).clamp(0.0, 1.0);
        final dyOffset = relativeDips[s0] * (1 - t) + relativeDips[s1] * t;

        for (var y = 0; y < h; y++) {
          final srcY = (y + dyOffset).clamp(0.0, (h - 1).toDouble());
          final iy = srcY.floor();
          final fy = srcY - iy;

          final p0 = straightened.getPixel(x, iy);
          final p1 = straightened.getPixel(x, (iy + 1).clamp(0, h - 1));

          final r = (p0.r * (1 - fy) + p1.r * fy).round().clamp(0, 255);
          final g = (p0.g * (1 - fy) + p1.g * fy).round().clamp(0, 255);
          final b = (p0.b * (1 - fy) + p1.b * fy).round().clamp(0, 255);

          dewarped.setPixelRgb(x, y, r, g, b);
        }
      }
    }

    // 3. Clear crease shadows and smooth paper surface
    return _smoothPaperSurfaceShading(dewarped);
  }

  /// Smooths out crease shadows and fold troughs to make paper surface smooth.
  static img.Image _smoothPaperSurfaceShading(img.Image src) {
    const bgDim = 32;
    final smallW = math.max(16, src.width ~/ bgDim);
    final smallH = math.max(16, src.height ~/ bgDim);
    final small = img.copyResize(src, width: smallW, height: smallH);

    final dilated = img.Image(width: smallW, height: smallH);
    const k = 2;
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        var maxR = 0, maxG = 0, maxB = 0;
        for (var dy = -k; dy <= k; dy++) {
          final ny = (y + dy).clamp(0, smallH - 1);
          for (var dx = -k; dx <= k; dx++) {
            final nx = (x + dx).clamp(0, smallW - 1);
            final p = small.getPixel(nx, ny);
            if (p.r > maxR) maxR = p.r.toInt();
            if (p.g > maxG) maxG = p.g.toInt();
            if (p.b > maxB) maxB = p.b.toInt();
          }
        }
        dilated.setPixelRgb(x, y, maxR, maxG, maxB);
      }
    }

    final blurred = img.gaussianBlur(dilated, radius: 4);
    final bgMap = img.copyResize(blurred, width: src.width, height: src.height);

    var sumBgLum = 0.0;
    var count = 0;
    for (var y = 0; y < smallH; y += 2) {
      for (var x = 0; x < smallW; x += 2) {
        final p = blurred.getPixel(x, y);
        sumBgLum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        count++;
      }
    }
    final targetLum = count > 0 ? (sumBgLum / count).clamp(210.0, 250.0) : 240.0;

    final out = src.clone();
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final bg = bgMap.getPixel(x, y);

        final bgR = math.max(20.0, bg.r.toDouble());
        final bgG = math.max(20.0, bg.g.toDouble());
        final bgB = math.max(20.0, bg.b.toDouble());

        final factorR = targetLum / bgR;
        final factorG = targetLum / bgG;
        final factorB = targetLum / bgB;

        final pLum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final bgLum = 0.299 * bgR + 0.587 * bgG + 0.114 * bgB;

        // Smooth crease shadow dips back to the flat paper luminance
        if (pLum > bgLum - 40) {
          final nr = (p.r * factorR).clamp(0.0, 255.0).toInt();
          final ng = (p.g * factorG).clamp(0.0, 255.0).toInt();
          final nb = (p.b * factorB).clamp(0.0, 255.0).toInt();
          out.setPixelRgb(x, y, nr, ng, nb);
        }
      }
    }

    return out;
  }

  /// Automatically dewarps and flattens bended/curled scan paper.
  static img.Image internalAutoFlattenPaper(img.Image src) {
    return internalAutoFlattenSmooth(src);
  }

  /// Adaptively adjusts brightness and contrast for dark/underexposed images.
  static img.Image internalAutoAdjustDarkImage(img.Image src) {
    final histogram = List.filled(256, 0);
    final totalPixels = src.width * src.height;
    var sumLum = 0.0;

    for (final p in src) {
      final lum =
          (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      histogram[lum]++;
      sumLum += lum;
    }

    final meanLum = sumLum / totalPixels;

    var count = 0;
    var p5 = 0;
    var p95 = 255;
    final count5 = (totalPixels * 0.05).round();
    final count95 = (totalPixels * 0.95).round();

    for (var i = 0; i < 256; i++) {
      count += histogram[i];
      if (p5 == 0 && count >= count5) p5 = i;
      if (count >= count95) {
        p95 = i;
        break;
      }
    }

    // Check if image is dark / underexposed
    final isUnderexposed = p95 < 210 || meanLum < 140;
    if (!isUnderexposed) {
      return src;
    }

    // Scale estimated paper white (p95) to clean readable white ~245
    const targetWhite = 245.0;
    final gain = (targetWhite / math.max(45.0, p95.toDouble())).clamp(1.0, 4.0);

    // Build S-curve tone mapping LUT
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      final v = i.toDouble() * gain;
      final norm = (v / 255.0).clamp(0.0, 1.0);
      final boosted =
          norm < 0.5 ? 2 * norm * norm : 1 - 2 * (1 - norm) * (1 - norm);
      final blended = norm * 0.4 + boosted * 0.6;
      lut[i] = (blended * 255.0).round().clamp(0, 255);
    }

    final result = src.clone();
    for (final p in result) {
      p.r = lut[p.r.toInt()];
      p.g = lut[p.g.toInt()];
      p.b = lut[p.b.toInt()];
    }

    return result;
  }

  /// Multi-scale 2D illumination normalization for shadows caused by antilights and harsh angles.
  static img.Image internalAutocorrectAntiLightShadows(img.Image src) {
    const bgDim = 48;
    final smallW = math.max(16, src.width ~/ bgDim);
    final smallH = math.max(16, src.height ~/ bgDim);

    final small = img.copyResize(src, width: smallW, height: smallH);

    // Morphological max dilation to estimate paper background color and remove dark text
    final dilated = img.Image(width: smallW, height: smallH);
    const k = 2;
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        var maxR = 0;
        var maxG = 0;
        var maxB = 0;
        for (var dy = -k; dy <= k; dy++) {
          final ny = (y + dy).clamp(0, smallH - 1);
          for (var dx = -k; dx <= k; dx++) {
            final nx = (x + dx).clamp(0, smallW - 1);
            final p = small.getPixel(nx, ny);
            if (p.r > maxR) maxR = p.r.toInt();
            if (p.g > maxG) maxG = p.g.toInt();
            if (p.b > maxB) maxB = p.b.toInt();
          }
        }
        dilated.setPixelRgb(x, y, maxR, maxG, maxB);
      }
    }

    // Gaussian blur for smooth illumination transition
    final blurred = img.gaussianBlur(dilated, radius: 4);
    final bgMap = img.copyResize(blurred, width: src.width, height: src.height);

    final result = src.clone();
    const targetBg = 246.0;

    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final bg = bgMap.getPixel(x, y);

        final bgR = math.max(25.0, bg.r.toDouble());
        final bgG = math.max(25.0, bg.g.toDouble());
        final bgB = math.max(25.0, bg.b.toDouble());

        final newR =
            ((p.r.toDouble() / bgR) * targetBg).clamp(0.0, 255.0).toInt();
        final newG =
            ((p.g.toDouble() / bgG) * targetBg).clamp(0.0, 255.0).toInt();
        final newB =
            ((p.b.toDouble() / bgB) * targetBg).clamp(0.0, 255.0).toInt();

        result.setPixelRgb(x, y, newR, newG, newB);
      }
    }

    return result;
  }

  /// Cheap uneven-illumination probe: stddev of a 12x12 luminance map.
  /// Gates shadow correction so evenly lit pages are never altered.
  static bool internalHasUnevenIllumination(img.Image src) {
    const cells = 12;
    final values = <double>[];
    for (var gy = 0; gy < cells; gy++) {
      for (var gx = 0; gx < cells; gx++) {
        final x0 = (gx * src.width / cells).floor();
        final x1 = (((gx + 1) * src.width / cells).floor())
            .clamp(0, src.width);
        final y0 = (gy * src.height / cells).floor();
        final y1 = (((gy + 1) * src.height / cells).floor())
            .clamp(0, src.height);
        var sum = 0.0;
        var count = 0;
        for (var y = y0; y < y1; y += 4) {
          for (var x = x0; x < x1; x += 4) {
            final p = src.getPixel(x, y);
            sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
            count++;
          }
        }
        if (count > 0) values.add(sum / count);
      }
    }
    if (values.isEmpty) return false;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance) > 12.0;
  }

  /// Straighten + auto-crop: warps a skewed paper quad to a rectangle and
  /// crops to the paper bounds. Near-rectangular detections fall back to the
  /// axis-aligned fit so flat pages are never warped.
  static img.Image internalFlattenStraighten(img.Image src) {
    final corners = internalDetectPaperCorners(src);
    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final tl = Offset(corners[0].dx * w, corners[0].dy * h);
    final tr = Offset(corners[1].dx * w, corners[1].dy * h);
    final br = Offset(corners[2].dx * w, corners[2].dy * h);
    final bl = Offset(corners[3].dx * w, corners[3].dy * h);

    final topSlope = (tr.dy - tl.dy) / math.max(1.0, tr.dx - tl.dx);
    final bottomSlope = (br.dy - bl.dy) / math.max(1.0, br.dx - bl.dx);
    final leftSlope = (bl.dx - tl.dx) / math.max(1.0, bl.dy - tl.dy);
    final rightSlope = (br.dx - tr.dx) / math.max(1.0, br.dy - tr.dy);

    final isNearRectangular = topSlope.abs() < 0.06 &&
        bottomSlope.abs() < 0.06 &&
        leftSlope.abs() < 0.06 &&
        rightSlope.abs() < 0.06;

    if (isNearRectangular) {
      return internalAutoFitPaper(src);
    }

    final outW = math
        .max(
          _dist(tl, tr),
          _dist(bl, br),
        )
        .round()
        .clamp(1, src.width);
    final outH = math
        .max(
          _dist(tl, bl),
          _dist(tr, br),
        )
        .round()
        .clamp(1, src.height);
    if (outW < 80 || outH < 80) return internalAutoFitPaper(src);

    final dst = [
      const Offset(0, 0),
      Offset(outW.toDouble(), 0),
      Offset(outW.toDouble(), outH.toDouble()),
      Offset(0, outH.toDouble()),
    ];
    final matrix = _homography([tl, tr, br, bl], dst);
    if (matrix == null) return internalAutoFitPaper(src);

    final result = img.Image(width: outW, height: outH);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final denom =
            matrix[6] * x + matrix[7] * y + matrix[8];
        if (denom.abs() < 1e-8) {
          result.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        final srcX = (matrix[0] * x + matrix[1] * y + matrix[2]) / denom;
        final srcY = (matrix[3] * x + matrix[4] * y + matrix[5]) / denom;
        if (srcX < 0 || srcY < 0 || srcX > w - 1 || srcY > h - 1) {
          result.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        final x0 = srcX.floor().clamp(0, src.width - 1);
        final y0 = srcY.floor().clamp(0, src.height - 1);
        final x1 = (x0 + 1).clamp(0, src.width - 1);
        final y1 = (y0 + 1).clamp(0, src.height - 1);
        final fx = (srcX - x0).clamp(0.0, 1.0);
        final fy = (srcY - y0).clamp(0.0, 1.0);
        final p00 = src.getPixel(x0, y0);
        final p10 = src.getPixel(x1, y0);
        final p01 = src.getPixel(x0, y1);
        final p11 = src.getPixel(x1, y1);
        result.setPixelRgb(
          x,
          y,
          _bilinear(p00.r.toDouble(), p10.r.toDouble(), p01.r.toDouble(),
              p11.r.toDouble(), fx, fy),
          _bilinear(p00.g.toDouble(), p10.g.toDouble(), p01.g.toDouble(),
              p11.g.toDouble(), fx, fy),
          _bilinear(p00.b.toDouble(), p10.b.toDouble(), p01.b.toDouble(),
              p11.b.toDouble(), fx, fy),
        );
      }
    }
    return result;
  }

  static double _dist(Offset a, Offset b) =>
      math.sqrt((a.dx - b.dx) * (a.dx - b.dx) +
          (a.dy - b.dy) * (a.dy - b.dy));

  static int _bilinear(
      double v00, double v10, double v01, double v11, double fx, double fy) {
    return ((v00 * (1 - fx) + v10 * fx) * (1 - fy) +
            (v01 * (1 - fx) + v11 * fx) * fy)
        .round()
        .clamp(0, 255);
  }

  /// Solves the 3x3 projective homography mapping [src] to [dst] (4 points
  /// each) via Gaussian elimination. Returns row-major h11..h33 or null.
  static List<double>? _homography(List<Offset> src, List<Offset> dst) {
    final a = List<List<double>>.generate(8, (_) => List.filled(9, 0.0));
    for (var i = 0; i < 4; i++) {
      final x = src[i].dx, y = src[i].dy;
      final u = dst[i].dx, v = dst[i].dy;
      a[i * 2][0] = x;
      a[i * 2][1] = y;
      a[i * 2][2] = 1;
      a[i * 2][6] = -u * x;
      a[i * 2][7] = -u * y;
      a[i * 2][8] = u;
      a[i * 2 + 1][3] = x;
      a[i * 2 + 1][4] = y;
      a[i * 2 + 1][5] = 1;
      a[i * 2 + 1][6] = -v * x;
      a[i * 2 + 1][7] = -v * y;
      a[i * 2 + 1][8] = v;
    }
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var row = col; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-10) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col] / a[col][col];
        for (var k = col; k < 9; k++) {
          a[row][k] -= factor * a[col][k];
        }
      }
    }
    final h = List<double>.filled(9, 0.0);
    for (var i = 0; i < 8; i++) {
      h[i] = a[i][8] / a[i][i];
    }
    h[8] = 1.0;
    return h;
  }
}
