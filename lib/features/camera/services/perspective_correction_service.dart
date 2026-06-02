import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

class PerspectiveCorrectionResult {
  const PerspectiveCorrectionResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

// Solve linear system using Gaussian elimination for 4x4 matrix
List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
  final n = a.length;
  for (var i = 0; i < n; i++) {
    var maxEl = a[i][i].abs();
    var maxRow = i;
    for (var k = i + 1; k < n; k++) {
      if (a[k][i].abs() > maxEl) {
        maxEl = a[k][i].abs();
        maxRow = k;
      }
    }

    final tmpRow = a[maxRow];
    a[maxRow] = a[i];
    a[i] = tmpRow;
    final tmpB = b[maxRow];
    b[maxRow] = b[i];
    b[i] = tmpB;

    for (var k = i + 1; k < n; k++) {
      final c = -a[k][i] / a[i][i];
      for (var j = i; j < n; j++) {
        if (i == j) {
          a[k][j] = 0;
        } else {
          a[k][j] += c * a[i][j];
        }
      }
      b[k] += c * b[i];
    }
  }

  final x = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    x[i] = b[i] / a[i][i];
    for (var k = i - 1; k >= 0; k--) {
      b[k] -= a[k][i] * x[i];
    }
  }
  return x;
}

Uint8List? _isolateCorrectPerspective(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final srcPts = params['srcPoints'] as List<Map<String, double>>;
  final targetWidth = params['targetWidth'] as int;
  final targetHeight = params['targetHeight'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Build perspective transform from source 4 corners to target rectangle
  // Using the direct linear transform (DLT) method
  final src = srcPts
      .map((p) => Offset(p['x']! * image.width, p['y']! * image.height))
      .toList();
  final dst = [
    Offset(0, 0),
    Offset(targetWidth.toDouble(), 0),
    Offset(targetWidth.toDouble(), targetHeight.toDouble()),
    Offset(0, targetHeight.toDouble()),
  ];

  // Compute perspective transform matrix
  final a = <List<double>>[];
  final b = <double>[];

  for (var i = 0; i < 4; i++) {
    a.add([
      src[i].dx, src[i].dy, 1, 0, 0, 0, -dst[i].dx * src[i].dx,
      -dst[i].dx * src[i].dy
    ]);
    b.add(dst[i].dx);
    a.add([
      0, 0, 0, src[i].dx, src[i].dy, 1, -dst[i].dy * src[i].dx,
      -dst[i].dy * src[i].dy
    ]);
    b.add(dst[i].dy);
  }

  final hParams = _solveLinearSystem(a, b);

  // 3x3 perspective matrix
  final h = [
    [hParams[0], hParams[1], hParams[2]],
    [hParams[3], hParams[4], hParams[5]],
    [hParams[6], hParams[7], 1.0],
  ];

  // Inverse perspective transform for each destination pixel
  // Compute inverse matrix
  final det = h[0][0] * (h[1][1] * h[2][2] - h[1][2] * h[2][1]) -
      h[0][1] * (h[1][0] * h[2][2] - h[1][2] * h[2][0]) +
      h[0][2] * (h[1][0] * h[2][1] - h[1][1] * h[2][0]);

  if (det.abs() < 1e-10) return null;

  final invDet = 1.0 / det;
  final hInv = <List<double>>[
    [
      (h[1][1] * h[2][2] - h[1][2] * h[2][1]) * invDet,
      (h[0][2] * h[2][1] - h[0][1] * h[2][2]) * invDet,
      (h[0][1] * h[1][2] - h[0][2] * h[1][1]) * invDet,
    ],
    [
      (h[1][2] * h[2][0] - h[1][0] * h[2][2]) * invDet,
      (h[0][0] * h[2][2] - h[0][2] * h[2][0]) * invDet,
      (h[0][2] * h[1][0] - h[0][0] * h[1][2]) * invDet,
    ],
    [
      (h[1][0] * h[2][1] - h[1][1] * h[2][0]) * invDet,
      (h[0][1] * h[2][0] - h[0][0] * h[2][1]) * invDet,
      (h[0][0] * h[1][1] - h[0][1] * h[1][0]) * invDet,
    ],
  ];

  final corrected = img.Image(width: targetWidth, height: targetHeight);
  final srcW = image.width;
  final srcH = image.height;

  for (var y = 0; y < targetHeight; y++) {
    for (var x = 0; x < targetWidth; x++) {
      final w = hInv[2][0] * x + hInv[2][1] * y + hInv[2][2];
      final sx = (hInv[0][0] * x + hInv[0][1] * y + hInv[0][2]) / w;
      final sy = (hInv[1][0] * x + hInv[1][1] * y + hInv[1][2]) / w;

      if (sx >= 0 && sx < srcW - 1 && sy >= 0 && sy < srcH - 1) {
        // Bilinear interpolation
        final ix = sx.floor();
        final iy = sy.floor();
        final fx = sx - ix;
        final fy = sy - iy;

        final p00 = image.getPixel(ix.clamp(0, srcW - 1), iy.clamp(0, srcH - 1));
        final p10 = image
            .getPixel((ix + 1).clamp(0, srcW - 1), iy.clamp(0, srcH - 1));
        final p01 = image
            .getPixel(ix.clamp(0, srcW - 1), (iy + 1).clamp(0, srcH - 1));
        final p11 = image.getPixel(
            (ix + 1).clamp(0, srcW - 1), (iy + 1).clamp(0, srcH - 1));

        final r = (p00.r * (1 - fx) * (1 - fy) +
                p10.r * fx * (1 - fy) +
                p01.r * (1 - fx) * fy +
                p11.r * fx * fy)
            .round()
            .clamp(0, 255);
        final g = (p00.g * (1 - fx) * (1 - fy) +
                p10.g * fx * (1 - fy) +
                p01.g * (1 - fx) * fy +
                p11.g * fx * fy)
            .round()
            .clamp(0, 255);
        final b = (p00.b * (1 - fx) * (1 - fy) +
                p10.b * fx * (1 - fy) +
                p01.b * (1 - fx) * fy +
                p11.b * fx * fy)
            .round()
            .clamp(0, 255);
        final a = (p00.a * (1 - fx) * (1 - fy) +
                p10.a * fx * (1 - fy) +
                p01.a * (1 - fx) * fy +
                p11.a * fx * fy)
            .round()
            .clamp(0, 255);

        corrected.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(corrected, quality: 92));
}

class PerspectiveCorrectionService {
  static Future<PerspectiveCorrectionResult?> correct({
    required Uint8List bytes,
    required List<Offset> srcPoints,
    int? targetWidth,
    int? targetHeight,
  }) async {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final tW = targetWidth ?? image.width;
    final tH = targetHeight ?? image.height;

    final srcMaps = srcPoints
        .map((p) => {'x': (p.dx / math.max(image.width, 1)).toDouble(), 'y': (p.dy / math.max(image.height, 1)).toDouble()})
        .toList();

    final result = await Isolate.run<Uint8List?>(() {
      return _isolateCorrectPerspective({
        'bytes': bytes,
        'srcPoints': srcMaps,
        'targetWidth': tW,
        'targetHeight': tH,
      });
    });

    if (result == null) return null;
    return PerspectiveCorrectionResult(
      bytes: result,
      width: tW,
      height: tH,
    );
  }
}
