import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Professional-grade object removal & inpainting service.
///
/// Uses confidence-based fast marching with gradient-aware propagation
/// and bilateral edge smoothing for high-quality results.
class MagicRemoveService {
  /// Inpaints selected masked areas on an image.
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

    // Downscale large images to prevent OOM (max 1024px on longest side)
    const maxDim = 1024;
    double downscaleFactor = 1.0;
    img.Image workImage = image;
    if (image.width > maxDim || image.height > maxDim) {
      downscaleFactor = maxDim / math.max(image.width, image.height);
      final newW = (image.width * downscaleFactor).round();
      final newH = (image.height * downscaleFactor).round();
      workImage = img.copyResize(image, width: newW, height: newH);
    }

    final width = workImage.width;
    final height = workImage.height;
    final totalPixels = width * height;

    final scaleX = width / imageWidth;
    final scaleY = height / imageHeight;
    final avgScale = (scaleX + scaleY) / 2.0;
    final scaledRadius = brushRadius * avgScale;

    // ── Step 1: Build mask from strokes ──
    final mask = Uint8List(totalPixels); // 0 = unmasked, 1 = masked

    void markCircle(double cx, double cy, double extraPad) {
      final r = scaledRadius + extraPad;
      final rSq = r * r;
      final minX = (cx - r).floor().clamp(0, width - 1);
      final maxX = (cx + r).ceil().clamp(0, width - 1);
      final minY = (cy - r).floor().clamp(0, height - 1);
      final maxY = (cy + r).ceil().clamp(0, height - 1);

      for (int y = minY; y <= maxY; y++) {
        final dy = y - cy;
        final dySq = dy * dy;
        final rowOffset = y * width;
        for (int x = minX; x <= maxX; x++) {
          final dx = x - cx;
          if (dx * dx + dySq <= rSq) {
            mask[rowOffset + x] = 1;
          }
        }
      }
    }

    // Connect points with interpolated strokes
    for (int i = 0; i < rawPoints.length; i += 2) {
      final px = rawPoints[i] * scaleX;
      final py = rawPoints[i + 1] * scaleY;
      markCircle(px, py, 0);

      if (i >= 2) {
        final prevPx = rawPoints[i - 2] * scaleX;
        final prevPy = rawPoints[i - 1] * scaleY;
        final dist = math.sqrt(
          (px - prevPx) * (px - prevPx) + (py - prevPy) * (py - prevPy),
        );
        final steps =
            (dist / math.max(1.0, scaledRadius / 2.0)).ceil().clamp(1, 200);
        for (int s = 1; s <= steps; s++) {
          final t = s / steps;
          markCircle(
            prevPx + (px - prevPx) * t,
            prevPy + (py - prevPy) * t,
            0,
          );
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

    // ── Step 2: Edge detection (Sobel) for gradient-aware filling ──
    final rArr = Uint8List(totalPixels);
    final gArr = Uint8List(totalPixels);
    final bArr = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final p = workImage.getPixel(x, y);
        final idx = rowOffset + x;
        rArr[idx] = p.r.toInt();
        gArr[idx] = p.g.toInt();
        bArr[idx] = p.b.toInt();
      }
    }

    // Compute grayscale for edge detection
    final gray = Float32List(totalPixels);
    for (int i = 0; i < totalPixels; i++) {
      gray[i] = 0.299 * rArr[i] + 0.587 * gArr[i] + 0.114 * bArr[i];
    }

    // Sobel edge magnitude
    final edgeMag = Float32List(totalPixels);
    for (int y = 1; y < height - 1; y++) {
      final rowOffset = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = rowOffset + x;
        final gx = -gray[(y - 1) * width + (x - 1)] +
            gray[(y - 1) * width + (x + 1)] -
            2 * gray[y * width + (x - 1)] +
            2 * gray[y * width + (x + 1)] -
            gray[(y + 1) * width + (x - 1)] +
            gray[(y + 1) * width + (x + 1)];
        final gy = -gray[(y - 1) * width + (x - 1)] -
            2 * gray[(y - 1) * width + x] -
            gray[(y - 1) * width + (x + 1)] +
            gray[(y + 1) * width + (x - 1)] +
            2 * gray[(y + 1) * width + x] +
            gray[(y + 1) * width + (x + 1)];
        edgeMag[idx] = math.sqrt(gx * gx + gy * gy);
      }
    }

    // ── Step 3: Smart mask dilation along edges ──
    // Expand mask slightly to cover nearby strong edges (absorbs object boundaries)
    final dilatedMask = Uint8List.fromList(mask);
    final edgeThreshold = 40.0;
    const dilateRadius = 3;
    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final idx = rowOffset + x;
        if (mask[idx] == 1) {
          // Check neighbors for strong edges
          final minY = (y - dilateRadius).clamp(0, height - 1);
          final maxY = (y + dilateRadius).clamp(0, height - 1);
          final minX = (x - dilateRadius).clamp(0, width - 1);
          final maxX = (x + dilateRadius).clamp(0, width - 1);
          for (int ny = minY; ny <= maxY; ny++) {
            for (int nx = minX; nx <= maxX; nx++) {
              final nIdx = ny * width + nx;
              if (edgeMag[nIdx] > edgeThreshold) {
                dilatedMask[nIdx] = 1;
              }
            }
          }
        }
      }
    }

    // ── Step 4: Confidence-based Fast Marching inpainting ──
    final state = Uint8List(totalPixels); // 0=KNOWN, 1=MASKED, 2=INPAINTED
    final confidence = Float32List(totalPixels);
    int maskedRemaining = 0;

    for (int i = 0; i < totalPixels; i++) {
      if (dilatedMask[i] == 1) {
        state[i] = 1;
        confidence[i] = 0.0;
        maskedRemaining++;
      } else {
        state[i] = 0;
        confidence[i] = 1.0; // Known pixels have full confidence
      }
    }

    const neighbors = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
      [-1, -1],
      [-1, 1],
      [1, -1],
      [1, 1],
    ];

    // Priority queue: higher confidence = process first (use negative for max-heap via simple sorted list)
    // We use a bucket queue for O(1) amortized insertion (confidence quantized to 0-1000)
    final buckets = List.generate(1001, (_) => <int>[]);
    int maxBucket = 0;
    int minBucket = 1000;

    void addToBucket(int pixelIdx, int conf) {
      conf = conf.clamp(0, 1000);
      buckets[conf].add(pixelIdx);
      if (conf > maxBucket) maxBucket = conf;
      if (conf < minBucket) minBucket = conf;
    }

    // Seed boundary pixels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (state[idx] == 1) {
          bool isBoundary = false;
          for (final n in neighbors) {
            final nx = x + n[0];
            final ny = y + n[1];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final nState = state[ny * width + nx];
              if (nState == 0 || nState == 2) {
                isBoundary = true;
                break;
              }
            }
          }
          if (isBoundary) {
            final conf = _computeConfidence(
              x, y, width, height, state, confidence, neighbors,
            );
            confidence[idx] = conf;
            addToBucket(idx, (conf * 1000).toInt());
          }
        }
      }
    }

    // Fast marching propagation
    while (maskedRemaining > 0) {
      // Find highest confidence bucket
      while (maxBucket >= minBucket && buckets[maxBucket].isEmpty) {
        maxBucket--;
      }
      if (maxBucket < minBucket) break;

      final batch = buckets[maxBucket];
      final currentBatch = List<int>.from(batch);
      batch.clear();

      for (final idx in currentBatch) {
        if (state[idx] != 1) continue;

        final x = idx % width;
        final y = idx ~/ width;

        // Gather gradient-weighted samples from known neighbors
        double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
        final searchR = 8;
        final minNvy = (y - searchR).clamp(0, height - 1);
        final maxNvy = (y + searchR).clamp(0, height - 1);
        final minNvx = (x - searchR).clamp(0, width - 1);
        final maxNvx = (x + searchR).clamp(0, width - 1);

        for (int ny = minNvy; ny <= maxNvy; ny++) {
          final nRowOff = ny * width;
          for (int nx = minNvx; nx <= maxNvx; nx++) {
            final nIdx = nRowOff + nx;
            final nState = state[nIdx];
            if (nState != 0 && nState != 2) continue;

            final dx = nx - x;
            final dy = ny - y;
            final d2 = dx * dx + dy * dy;

            // Confidence weight
            final confW = confidence[nIdx];

            // Gradient-aware weight: prefer samples along gradient direction
            // (reduces bleeding across edges)
            final edgeW = 1.0 / (1.0 + edgeMag[nIdx] * 0.02);

            // Distance weight
            final distW = 1.0 / (d2 + 1.0);

            // Directional weight: prefer samples in same gradient direction
            final dirW = _directionalWeight(
              x, y, nx, ny, width, height, gray,
            );

            final w = confW * edgeW * distW * dirW;
            sumR += rArr[nIdx] * w;
            sumG += gArr[nIdx] * w;
            sumB += bArr[nIdx] * w;
            sumW += w;
          }
        }

        if (sumW > 0) {
          rArr[idx] = (sumR / sumW).round().clamp(0, 255);
          gArr[idx] = (sumG / sumW).round().clamp(0, 255);
          bArr[idx] = (sumB / sumW).round().clamp(0, 255);
          state[idx] = 2; // INPAINTED
          maskedRemaining--;

          // Update confidence of newly inpainted pixel
          confidence[idx] = _computeConfidence(
            x, y, width, height, state, confidence, neighbors,
          );

          // Add unmasked neighbors to boundary
          for (final n in neighbors) {
            final nx = x + n[0];
            final ny = y + n[1];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final nIdx = ny * width + nx;
              if (state[nIdx] == 1) {
                final nConf = _computeConfidence(
                  nx, ny, width, height, state, confidence, neighbors,
                );
                confidence[nIdx] = nConf;
                addToBucket(nIdx, (nConf * 1000).toInt());
              }
            }
          }
        }
      }
    }

    // ── Step 5: Bilateral edge-preserving smoothing ──
    // Collect inpainted region boundary
    final smoothRegion = Uint8List(totalPixels);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (state[idx] == 2) {
          for (final n in neighbors) {
            final nx = x + n[0];
            final ny = y + n[1];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              if (state[ny * width + nx] == 0) {
                // Mark this inpainted pixel and nearby for smoothing
                const sr = 3;
                final minY = (y - sr).clamp(0, height - 1);
                final maxY = (y + sr).clamp(0, height - 1);
                final minX = (x - sr).clamp(0, width - 1);
                final maxX = (x + sr).clamp(0, width - 1);
                for (int sy = minY; sy <= maxY; sy++) {
                  for (int sx = minX; sx <= maxX; sx++) {
                    smoothRegion[sy * width + sx] = 1;
                  }
                }
                break;
              }
            }
          }
        }
      }
    }

    // Bilateral filter: edge-preserving smoothing with larger kernel
    for (int pass = 0; pass < 3; pass++) {
      final tempR = Uint8List.fromList(rArr);
      final tempG = Uint8List.fromList(gArr);
      final tempB = Uint8List.fromList(bArr);

      for (int y = 3; y < height - 3; y++) {
        final yRow = y * width;
        for (int x = 3; x < width - 3; x++) {
          final idx = yRow + x;
          if (smoothRegion[idx] != 1) continue;

          double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
          final centerGray = gray[idx];

          for (int ky = -3; ky <= 3; ky++) {
            final kRow = (y + ky) * width;
            for (int kx = -3; kx <= 3; kx++) {
              final nIdx = kRow + (x + kx);
              final d2 = kx * kx + ky * ky;

              final spatialW = math.exp(-d2 / 8.0);
              final colorDiff = (gray[nIdx] - centerGray).abs();
              final rangeW = math.exp(-colorDiff * colorDiff / 350.0);

              final w = spatialW * rangeW;
              sumR += tempR[nIdx] * w;
              sumG += tempG[nIdx] * w;
              sumB += tempB[nIdx] * w;
              sumW += w;
            }
          }

          if (sumW > 0) {
            rArr[idx] = (sumR / sumW).round().clamp(0, 255);
            gArr[idx] = (sumG / sumW).round().clamp(0, 255);
            bArr[idx] = (sumB / sumW).round().clamp(0, 255);
          }
        }
      }
    }

    // Edge feathering: smooth transitions at the boundary of inpainted region
    final featherRegion = Uint8List(totalPixels);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (state[idx] != 0) continue;
        bool touchesInpainted = false;
        for (final n in neighbors) {
          final nx = x + n[0];
          final ny = y + n[1];
          if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
            if (state[ny * width + nx] == 2) {
              touchesInpainted = true;
              break;
            }
          }
        }
        if (touchesInpainted) {
          const fr = 4;
          final minY = (y - fr).clamp(0, height - 1);
          final maxY = (y + fr).clamp(0, height - 1);
          final minX = (x - fr).clamp(0, width - 1);
          final maxX = (x + fr).clamp(0, width - 1);
          for (int fy = minY; fy <= maxY; fy++) {
            for (int fx = minX; fx <= maxX; fx++) {
              featherRegion[fy * width + fx] = 1;
            }
          }
        }
      }
    }

    for (int pass = 0; pass < 2; pass++) {
      final tempR = Uint8List.fromList(rArr);
      final tempG = Uint8List.fromList(gArr);
      final tempB = Uint8List.fromList(bArr);

      for (int y = 2; y < height - 2; y++) {
        final yRow = y * width;
        for (int x = 2; x < width - 2; x++) {
          final idx = yRow + x;
          if (featherRegion[idx] != 1) continue;

          double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
          final centerGray = gray[idx];

          for (int ky = -2; ky <= 2; ky++) {
            final kRow = (y + ky) * width;
            for (int kx = -2; kx <= 2; kx++) {
              final nIdx = kRow + (x + kx);
              final d2 = kx * kx + ky * ky;

              final spatialW = math.exp(-d2 / 3.0);
              final colorDiff = (gray[nIdx] - centerGray).abs();
              final rangeW = math.exp(-colorDiff * colorDiff / 600.0);

              final w = spatialW * rangeW;
              sumR += tempR[nIdx] * w;
              sumG += tempG[nIdx] * w;
              sumB += tempB[nIdx] * w;
              sumW += w;
            }
          }

          if (sumW > 0) {
            rArr[idx] = (sumR / sumW).round().clamp(0, 255);
            gArr[idx] = (sumG / sumW).round().clamp(0, 255);
            bArr[idx] = (sumB / sumW).round().clamp(0, 255);
          }
        }
      }
    }

    // ── Step 6: Write back to image ──
    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        final idx = rowOffset + x;
        workImage.setPixelRgb(x, y, rArr[idx], gArr[idx], bArr[idx]);
      }
    }

    // Upscale back to original dimensions if we downscaled
    img.Image resultImage = workImage;
    if (downscaleFactor < 1.0) {
      resultImage = img.copyResize(
        workImage,
        width: image.width,
        height: image.height,
        interpolation: img.Interpolation.linear,
      );
    }

    return Uint8List.fromList(img.encodeJpg(resultImage, quality: 95));
  }

  /// Compute confidence for a pixel based on known neighbors.
  static double _computeConfidence(
    int x,
    int y,
    int width,
    int height,
    Uint8List state,
    Float32List confidence,
    List<List<int>> neighbors,
  ) {
    double sumConf = 0;
    int count = 0;
    for (final n in neighbors) {
      final nx = x + n[0];
      final ny = y + n[1];
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
        final nState = state[ny * width + nx];
        if (nState == 0 || nState == 2) {
          sumConf += confidence[ny * width + nx];
          count++;
        }
      }
    }
    return count > 0 ? sumConf / count * 0.95 : 0.0;
  }

  /// Directional weight: prefer samples aligned with local gradient.
  static double _directionalWeight(
    int x1,
    int y1,
    int x2,
    int y2,
    int width,
    int height,
    Float32List gray,
  ) {
    // Simple gradient-based direction matching
    // Samples in the same gradient direction contribute more
    final dx = x2 - x1;
    final dy = y2 - y1;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return 1.0;

    // Check gradient at source pixel
    if (x1 < 1 || x1 >= width - 1 || y1 < 1 || y1 >= height - 1) {
      return 1.0;
    }

    final gx = -gray[(y1 - 1) * width + (x1 - 1)] +
        gray[(y1 - 1) * width + (x1 + 1)] -
        2 * gray[y1 * width + (x1 - 1)] +
        2 * gray[y1 * width + (x1 + 1)] -
        gray[(y1 + 1) * width + (x1 - 1)] +
        gray[(y1 + 1) * width + (x1 + 1)];
    final gy = -gray[(y1 - 1) * width + (x1 - 1)] -
        2 * gray[(y1 - 1) * width + x1] -
        gray[(y1 - 1) * width + (x1 + 1)] +
        gray[(y1 + 1) * width + (x1 - 1)] +
        2 * gray[(y1 + 1) * width + x1] +
        gray[(y1 + 1) * width + (x1 + 1)];

    final gLen = math.sqrt(gx * gx + gy * gy);
    if (gLen < 1) return 1.0;

    // Normalize direction
    final gnx = gx / gLen;
    final gny = gy / gLen;

    // Dot product between sample direction and gradient direction
    final dot = (dx / dist) * gnx + (dy / dist) * gny;

    // If sample is along gradient (perpendicular to edge), boost weight
    // If sample is across gradient (along edge), reduce weight slightly
    return 0.5 + 0.5 * dot.abs();
  }
}
