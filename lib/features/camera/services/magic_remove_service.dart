import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Offline object eraser & auto-heal inpainting service.
class MagicRemoveService {
  /// Inpaints selected masked areas on an image using boundary propagation
  /// and edge smoothing.
  ///
  /// Executes on a background isolate to keep UI responsive.
  static Future<Uint8List?> inpaintObject({
    required Uint8List imageBytes,
    required List<Offset> points,
    required double brushRadius,
    required double imageWidth,
    required double imageHeight,
  }) async {
    if (points.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return imageBytes;
    }

    final rawPoints = <double>[];
    for (final p in points) {
      rawPoints.add(p.dx);
      rawPoints.add(p.dy);
    }

    return Isolate.run(() {
      return _inpaintInternal(
        imageBytes: imageBytes,
        rawPoints: rawPoints,
        brushRadius: brushRadius,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    });
  }

  static Uint8List? _inpaintInternal({
    required Uint8List imageBytes,
    required List<double> rawPoints,
    required double brushRadius,
    required double imageWidth,
    required double imageHeight,
  }) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;

    final scaleX = width / imageWidth;
    final scaleY = height / imageHeight;
    final avgScale = (scaleX + scaleY) / 2.0;
    final scaledRadius = brushRadius * avgScale;
    final scaledRadiusSq = scaledRadius * scaledRadius;

    // Create 2D binary mask
    final mask = Uint8List(totalPixels); // 0 = unmasked, 1 = masked

    void markCircle(double cx, double cy) {
      final minX = (cx - scaledRadius).floor().clamp(0, width - 1);
      final maxX = (cx + scaledRadius).ceil().clamp(0, width - 1);
      final minY = (cy - scaledRadius).floor().clamp(0, height - 1);
      final maxY = (cy + scaledRadius).ceil().clamp(0, height - 1);

      for (int y = minY; y <= maxY; y++) {
        final dy = y - cy;
        final dySq = dy * dy;
        final rowOffset = y * width;
        for (int x = minX; x <= maxX; x++) {
          final dx = x - cx;
          if (dx * dx + dySq <= scaledRadiusSq) {
            mask[rowOffset + x] = 1;
          }
        }
      }
    }

    // Connect points with strokes
    for (int i = 0; i < rawPoints.length; i += 2) {
      final px = rawPoints[i] * scaleX;
      final py = rawPoints[i + 1] * scaleY;
      markCircle(px, py);

      if (i >= 2) {
        final prevPx = rawPoints[i - 2] * scaleX;
        final prevPy = rawPoints[i - 1] * scaleY;

        final dist = math.sqrt(
          (px - prevPx) * (px - prevPx) + (py - prevPy) * (py - prevPy),
        );
        final steps = (dist / math.max(1.0, scaledRadius / 2.0)).ceil().clamp(1, 200);
        for (int s = 1; s <= steps; s++) {
          final interpX = prevPx + (px - prevPx) * (s / steps);
          final interpY = prevPy + (py - prevPy) * (s / steps);
          markCircle(interpX, interpY);
        }
      }
    }

    // Check if any pixels are masked
    bool hasMask = false;
    for (int i = 0; i < totalPixels; i++) {
      if (mask[i] == 1) {
        hasMask = true;
        break;
      }
    }
    if (!hasMask) return imageBytes;

    // Extract color arrays for fast access
    final rArr = Uint8List(totalPixels);
    final gArr = Uint8List(totalPixels);
    final bArr = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final p = image.getPixel(x, y);
        final idx = rowOffset + x;
        rArr[idx] = p.r.toInt();
        gArr[idx] = p.g.toInt();
        bArr[idx] = p.b.toInt();
      }
    }

    // State array: 0 = KNOWN, 1 = MASKED, 2 = INPAINTED
    final state = Uint8List(totalPixels);
    int maskedRemaining = 0;
    for (int i = 0; i < totalPixels; i++) {
      if (mask[i] == 1) {
        state[i] = 1;
        maskedRemaining++;
      } else {
        state[i] = 0;
      }
    }

    const searchRadius = 8;
    const searchRadiusSq = searchRadius * searchRadius;
    const neighbors = [
      [-1, 0], [1, 0], [0, -1], [0, 1],
      [-1, -1], [-1, 1], [1, -1], [1, 1]
    ];

    // Collect initial mask boundary pixels for multi-pass smoothing later
    final initialBoundary = <int>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (state[idx] == 1) {
          for (final n in neighbors) {
            final nx = x + n[0];
            final ny = y + n[1];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              if (state[ny * width + nx] == 0) {
                initialBoundary.add(idx);
                break;
              }
            }
          }
        }
      }
    }

    // Layer-by-layer inward propagation
    while (maskedRemaining > 0) {
      final currentBoundary = <int>[];
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = y * width + x;
          if (state[idx] == 1) {
            bool isCurrentBoundary = false;
            for (final n in neighbors) {
              final nx = x + n[0];
              final ny = y + n[1];
              if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                final nState = state[ny * width + nx];
                if (nState == 0 || nState == 2) {
                  isCurrentBoundary = true;
                  break;
                }
              }
            }
            if (isCurrentBoundary) {
              currentBoundary.add(idx);
            }
          }
        }
      }

      if (currentBoundary.isEmpty) break;

      for (final idx in currentBoundary) {
        final x = idx % width;
        final y = idx ~/ width;

        double sumR = 0;
        double sumG = 0;
        double sumB = 0;
        double sumW = 0;

        final minY = (y - searchRadius).clamp(0, height - 1);
        final maxY = (y + searchRadius).clamp(0, height - 1);
        final minX = (x - searchRadius).clamp(0, width - 1);
        final maxX = (x + searchRadius).clamp(0, width - 1);

        for (int ny = minY; ny <= maxY; ny++) {
          final dy = ny - y;
          final dySq = dy * dy;
          final rowOffset = ny * width;
          for (int nx = minX; nx <= maxX; nx++) {
            final dx = nx - x;
            final d2 = dx * dx + dySq;
            if (d2 > searchRadiusSq) continue;

            final nIdx = rowOffset + nx;
            final nState = state[nIdx];
            if (nState == 0 || nState == 2) {
              final w = 1.0 / (d2 + 1.0);
              sumR += rArr[nIdx] * w;
              sumG += gArr[nIdx] * w;
              sumB += bArr[nIdx] * w;
              sumW += w;
            }
          }
        }

        if (sumW > 0) {
          rArr[idx] = (sumR / sumW).round().clamp(0, 255);
          gArr[idx] = (sumG / sumW).round().clamp(0, 255);
          bArr[idx] = (sumB / sumW).round().clamp(0, 255);
          state[idx] = 2; // INPAINTED
          maskedRemaining--;
        }
      }
    }

    // Multi-pass Gaussian edge smoothing along the mask boundary
    final smoothRegion = Uint8List(totalPixels);
    for (final bIdx in initialBoundary) {
      final bx = bIdx % width;
      final by = bIdx ~/ width;
      const smoothRadius = 4;
      final minY = (by - smoothRadius).clamp(0, height - 1);
      final maxY = (by + smoothRadius).clamp(0, height - 1);
      final minX = (bx - smoothRadius).clamp(0, width - 1);
      final maxX = (bx + smoothRadius).clamp(0, width - 1);

      for (int sy = minY; sy <= maxY; sy++) {
        final sRow = sy * width;
        for (int sx = minX; sx <= maxX; sx++) {
          smoothRegion[sRow + sx] = 1;
        }
      }
    }

    // Perform 3 passes of 3x3 Gaussian smoothing over smoothRegion
    for (int pass = 0; pass < 3; pass++) {
      final tempR = Uint8List.fromList(rArr);
      final tempG = Uint8List.fromList(gArr);
      final tempB = Uint8List.fromList(bArr);

      for (int y = 1; y < height - 1; y++) {
        final yRow = y * width;
        for (int x = 1; x < width - 1; x++) {
          final idx = yRow + x;
          if (smoothRegion[idx] != 1) continue;

          int sumR = 0, sumG = 0, sumB = 0;
          const kernel = [
            [1, 2, 1],
            [2, 4, 2],
            [1, 2, 1]
          ];
          for (int ky = -1; ky <= 1; ky++) {
            final kRow = (y + ky) * width;
            for (int kx = -1; kx <= 1; kx++) {
              final nIdx = kRow + (x + kx);
              final weight = kernel[ky + 1][kx + 1];
              sumR += tempR[nIdx] * weight;
              sumG += tempG[nIdx] * weight;
              sumB += tempB[nIdx] * weight;
            }
          }

          rArr[idx] = (sumR >> 4).clamp(0, 255);
          gArr[idx] = (sumG >> 4).clamp(0, 255);
          bArr[idx] = (sumB >> 4).clamp(0, 255);
        }
      }
    }

    // Write back to image
    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final idx = rowOffset + x;
        image.setPixelRgb(x, y, rArr[idx], gArr[idx], bArr[idx]);
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }
}
