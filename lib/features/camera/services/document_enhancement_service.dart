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

  /// All-in-one smart scan enhancement with per-stage detection gating.
  /// Only stages that actually detect a problem run; the returned [stages]
  /// list names exactly what was applied so the UI never claims work it
  /// did not do.
  static Future<SmartEnhanceResult?> smartScanEnhanceDetailed(
    Uint8List bytes,
  ) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final stages = <String>[];
      img.Image processed = image;

      final fitted = internalAutoFitPaper(processed);
      if (!identical(fitted, processed)) stages.add('Auto-crop');
      processed = fitted;

      final flat = internalAutoFlattenPaper(processed);
      if (!identical(flat, processed)) stages.add('Flatten');
      processed = flat;

      if (internalHasUnevenIllumination(processed)) {
        processed = internalAutocorrectAntiLightShadows(processed);
        stages.add('Shadow removal');
      }

      final brightened = internalAutoAdjustDarkImage(processed);
      if (!identical(brightened, processed)) stages.add('Brightness');
      processed = brightened;

      return SmartEnhanceResult(
        bytes: Uint8List.fromList(img.encodeJpg(processed, quality: 95)),
        stages: stages,
      );
    });
  }

  /// All-in-one smart scan enhancement:
  /// Auto-fit paper + Auto-flatten curvature + Correct antilight shadows + Auto-adjust brightness/contrast
  static Future<Uint8List?> smartScanEnhance(Uint8List bytes) async {
    final result = await smartScanEnhanceDetailed(bytes);
    return result?.bytes;
  }

  /// Flatten = straighten + auto-crop to the paper bounds (NOT a curvature
  /// dewarp). Warps a skewed paper quad into a rectangle, then crops to the
  /// detected paper edges. Flat pages pass through untouched.
  static Future<Uint8List?> flattenDocument(Uint8List bytes) async {
    return Isolate.run(() {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final flattened = internalFlattenStraighten(image);
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

  /// Automatically dewarps and flattens bended/curled scan paper.
  static img.Image internalAutoFlattenPaper(img.Image src) {
    final w = src.width;
    final h = src.height;

    // Analyze vertical baseline curvature across horizontal slices
    const numSlices = 20;
    final sliceWidth = w / numSlices;
    final detectedOffsets = List<double>.filled(numSlices, 0.0);

    for (var s = 0; s < numSlices; s++) {
      final startX = (s * sliceWidth).round().clamp(0, w - 1);
      final endX = ((s + 1) * sliceWidth).round().clamp(0, w - 1);

      var weightSum = 0.0;
      var yWeightedSum = 0.0;

      for (var y = 0; y < h; y++) {
        for (var x = startX; x < endX; x++) {
          final p = src.getPixel(x, y);
          final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          // Document content (text/lines) is darker than paper background
          if (lum < 165) {
            final darkness = (165 - lum);
            weightSum += darkness;
            yWeightedSum += darkness * y;
          }
        }
      }

      if (weightSum > 40) {
        detectedOffsets[s] = yWeightedSum / weightSum;
      } else {
        detectedOffsets[s] = h / 2.0;
      }
    }

    // A text-heavy column can shift its dark-pixel centre independently of
    // neighbouring columns.  Treating those local shifts as paper curvature
    // was the cause of the previous wavy result. Keep only the broad, smooth
    // component before considering a dewarp.
    final smoothedOffsets = List<double>.filled(numSlices, 0.0);
    for (var i = 0; i < numSlices; i++) {
      var weightedSum = 0.0;
      var weight = 0.0;
      for (var j = math.max(0, i - 3);
          j <= math.min(numSlices - 1, i + 3);
          j++) {
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

    // Be conservative: a scanner should preserve a flat page rather than
    // inventing a warp from normal paragraph/table layout.
    if (curveAmplitude < (h * 0.015) || curveAmplitude > (h * 0.12)) {
      return src;
    }

    final result = img.Image(width: w, height: h);

    // Dewarp: for every destination column, reverse the vertical curvature dip
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

        final p0 = src.getPixel(x, iy);
        final p1 = src.getPixel(x, (iy + 1).clamp(0, h - 1));

        final r = (p0.r * (1 - fy) + p1.r * fy).round().clamp(0, 255);
        final g = (p0.g * (1 - fy) + p1.g * fy).round().clamp(0, 255);
        final b = (p0.b * (1 - fy) + p1.b * fy).round().clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }

    return result;
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
