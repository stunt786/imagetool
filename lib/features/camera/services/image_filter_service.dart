import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/scanned_page.dart';
import 'document_enhancement_service.dart';

class ImageFilterResult {
  const ImageFilterResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

Uint8List? _isolateApplyPreview(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final filterName = params['filter'] as String;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  const maxPreviewDimension = 900;
  final longest = math.max(decoded.width, decoded.height);
  final preview = longest > maxPreviewDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxPreviewDimension : null,
          height: decoded.height > decoded.width ? maxPreviewDimension : null,
        )
      : decoded;
  final previewBytes = Uint8List.fromList(img.encodeJpg(preview, quality: 82));

  return _isolateApplyFilter({'bytes': previewBytes, 'filter': filterName});
}

Uint8List? _isolateApplyMagicColor(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Scanner-grade color: CLAHE on luminance for local contrast plus a gentle
  // saturation/exposure lift. Unlike a single global adjustColor curve this
  // recovers text in shadows without blowing out bright paper.
  img.Image processed = _claheLuminance(image);
  processed = img.adjustColor(processed, saturation: 1.18, brightness: 1.02);

  return Uint8List.fromList(img.encodeJpg(processed, quality: 92));
}

/// Contrast-Limited Adaptive Histogram Equalization applied to luminance
/// only (8x8 tiles, clip 2.0), preserving hue via per-pixel RGB rescaling.
img.Image _claheLuminance(img.Image src) {
  const tiles = 8;
  const clip = 2.0;
  final w = src.width, h = src.height;
  final lum = List<double>.generate(
    w * h,
    (i) {
      final p = src.getPixel(i % w, i ~/ w);
      return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    },
  );

  final tileW = (w / tiles).ceil(), tileH = (h / tiles).ceil();
  // Per-tile clipped CDF LUTs.
  final luts = <List<int>>[];
  for (var ty = 0; ty < tiles; ty++) {
    for (var tx = 0; tx < tiles; tx++) {
      final hist = List<int>.filled(256, 0);
      var count = 0;
      for (var y = ty * tileH; y < math.min((ty + 1) * tileH, h); y++) {
        for (var x = tx * tileW; x < math.min((tx + 1) * tileW, w); x++) {
          hist[lum[y * w + x].round().clamp(0, 255)]++;
          count++;
        }
      }
      if (count == 0) {
        luts.add(List<int>.generate(256, (i) => i));
        continue;
      }
      final limit = math.max(1, (clip * count / 256).round());
      var excess = 0;
      for (var i = 0; i < 256; i++) {
        if (hist[i] > limit) {
          excess += hist[i] - limit;
          hist[i] = limit;
        }
      }
      final redistribute = excess ~/ 256;
      final remainder = excess % 256;
      for (var i = 0; i < 256; i++) {
        hist[i] += redistribute + (i < remainder ? 1 : 0);
      }
      final lut = List<int>.filled(256, 0);
      var cdf = 0;
      final cdfMin = hist.firstWhere((v) => v > 0, orElse: () => 0);
      for (var i = 0; i < 256; i++) {
        cdf += hist[i];
        lut[i] = count <= cdfMin
            ? i
            : (((cdf - cdfMin) / (count - cdfMin)) * 255)
                .round()
                .clamp(0, 255);
      }
      luts.add(lut);
    }
  }

  int sampleLut(double x, double y, int level) {
    final tx = (x * tiles / w - 0.5).clamp(0.0, tiles - 1.001);
    final ty = (y * tiles / h - 0.5).clamp(0.0, tiles - 1.001);
    final x0 = tx.floor(), y0 = ty.floor();
    final x1 = math.min(x0 + 1, tiles - 1), y1 = math.min(y0 + 1, tiles - 1);
    final fx = (tx - x0).clamp(0.0, 1.0), fy = (ty - y0).clamp(0.0, 1.0);
    final v00 = luts[y0 * tiles + x0][level].toDouble();
    final v10 = luts[y0 * tiles + x1][level].toDouble();
    final v01 = luts[y1 * tiles + x0][level].toDouble();
    final v11 = luts[y1 * tiles + x1][level].toDouble();
    return ((v00 * (1 - fx) + v10 * fx) * (1 - fy) +
            (v01 * (1 - fx) + v11 * fx) * fy)
        .round()
        .clamp(0, 255);
  }

  final out = src.clone();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final oldL = lum[y * w + x];
      if (oldL < 1) continue;
      final newL = sampleLut(x.toDouble(), y.toDouble(), oldL.round().clamp(0, 255));
      final scale = (newL / oldL).clamp(0.25, 3.0);
      out.setPixelRgb(
        x,
        y,
        (p.r * scale).round().clamp(0, 255),
        (p.g * scale).round().clamp(0, 255),
        (p.b * scale).round().clamp(0, 255),
      );
    }
  }
  return out;
}

Uint8List? _isolateApplyBinarization(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Sauvola adaptive thresholding (window 25, k 0.34): unlike global Otsu it
  // keeps text legible under gradients and hand shadows. Integral images keep
  // it O(1) per pixel.
  final processed = _sauvolaBinarize(img.grayscale(image));

  return Uint8List.fromList(img.encodeJpg(processed, quality: 95));
}

img.Image _sauvolaBinarize(img.Image gray, {int window = 25, double k = 0.34}) {
  final w = gray.width, h = gray.height;
  final integral = List<double>.filled((w + 1) * (h + 1), 0.0);
  final integralSq = List<double>.filled((w + 1) * (h + 1), 0.0);
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0, rowSumSq = 0.0;
    for (var x = 0; x < w; x++) {
      final v = gray.getPixel(x, y).r.toDouble();
      rowSum += v;
      rowSumSq += v * v;
      integral[(y + 1) * (w + 1) + x + 1] =
          integral[y * (w + 1) + x + 1] + rowSum;
      integralSq[(y + 1) * (w + 1) + x + 1] =
          integralSq[y * (w + 1) + x + 1] + rowSumSq;
    }
  }

  double rectSum(List<double> ii, int x0, int y0, int x1, int y1) =>
      ii[y1 * (w + 1) + x1] -
      ii[y0 * (w + 1) + x1] -
      ii[y1 * (w + 1) + x0] +
      ii[y0 * (w + 1) + x0];

  final half = window ~/ 2;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - half), y1 = math.min(h, y + half + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - half), x1 = math.min(w, x + half + 1);
      final area = (x1 - x0) * (y1 - y0);
      final mean = rectSum(integral, x0, y0, x1, y1) / area;
      final meanSq = rectSum(integralSq, x0, y0, x1, y1) / area;
      final std = math.sqrt(math.max(0.0, meanSq - mean * mean));
      final threshold = mean * (1 + k * (std / 128 - 1));
      final v = gray.getPixel(x, y).r.toDouble();
      final ink = v <= threshold;
      out.setPixelRgba(x, y, ink ? 0 : 255, ink ? 0 : 255, ink ? 0 : 255, 255);
    }
  }
  return out;
}

Uint8List? _isolateApplyShadowRemoval(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final gray = img.grayscale(image);

  // Illumination estimation via morphological closing (dilate then erode) on
  // a downsampled copy: removes text cleanly without the halo a pure
  // dilation leaves around dark regions.
  const bgDim = 64;
  final smallW = math.max(16, gray.width ~/ bgDim);
  final smallH = math.max(16, gray.height ~/ bgDim);
  final small = img.copyResize(gray, width: smallW, height: smallH);
  final dilated = img.Image(width: smallW, height: smallH);
  const k = 2;
  for (var y = 0; y < smallH; y++) {
    for (var x = 0; x < smallW; x++) {
      var maxV = 0;
      for (var dy = -k; dy <= k; dy++) {
        final ny = (y + dy).clamp(0, smallH - 1);
        for (var dx = -k; dx <= k; dx++) {
          final nx = (x + dx).clamp(0, smallW - 1);
          final v = small.getPixel(nx, ny).r.toInt();
          if (v > maxV) maxV = v;
        }
      }
      dilated.setPixelRgba(x, y, maxV, maxV, maxV, 255);
    }
  }
  final closed = img.Image(width: smallW, height: smallH);
  for (var y = 0; y < smallH; y++) {
    for (var x = 0; x < smallW; x++) {
      var minV = 255;
      for (var dy = -k; dy <= k; dy++) {
        final ny = (y + dy).clamp(0, smallH - 1);
        for (var dx = -k; dx <= k; dx++) {
          final nx = (x + dx).clamp(0, smallW - 1);
          final v = dilated.getPixel(nx, ny).r.toInt();
          if (v < minV) minV = v;
        }
      }
      closed.setPixelRgba(x, y, minV, minV, minV, 255);
    }
  }
  final blurredSmall = img.gaussianBlur(closed, radius: 4);
  final bg = img.copyResize(blurredSmall, width: gray.width, height: gray.height);

  // Division normalization to flatten uneven shadows into clean document background
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      final orig = gray.getPixel(x, y).r.toDouble();
      final bgVal = bg.getPixel(x, y).r.toDouble().clamp(1.0, 255.0);
      final val = ((orig / bgVal) * 235.0).clamp(0.0, 255.0).toInt();
      gray.setPixelRgba(x, y, val, val, val, 255);
    }
  }

  final processed = img.adjustColor(gray, contrast: 1.15, brightness: 1.05);
  return Uint8List.fromList(img.encodeJpg(processed, quality: 92));
}

Uint8List? _isolateApplyFilter(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final filterName = params['filter'] as String;
  if (filterName == 'magicColor') return _isolateApplyMagicColor(params);
  if (filterName == 'binarization' || filterName == 'blackWhite') {
    return _isolateApplyBinarization(params);
  }
  if (filterName == 'shadowRemoval' || filterName == 'noShadow') {
    return _isolateApplyShadowRemoval(params);
  }
  if (filterName == 'autoFlatten') {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final flattened = DocumentEnhancementService.internalAutoFlattenPaper(image);
    return Uint8List.fromList(img.encodeJpg(flattened, quality: 92));
  }
  if (filterName == 'antiLight') {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final corrected = DocumentEnhancementService.internalAutocorrectAntiLightShadows(image);
    return Uint8List.fromList(img.encodeJpg(corrected, quality: 92));
  }
  if (filterName == 'autoBrighten') {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final brightened = DocumentEnhancementService.internalAutoAdjustDarkImage(image);
    return Uint8List.fromList(img.encodeJpg(brightened, quality: 92));
  }
  if (filterName == 'smartScan') {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    // Same gated pipeline as Smart Fix: never alter what is already clean.
    var processed = DocumentEnhancementService.internalAutoFitPaper(image);
    processed =
        DocumentEnhancementService.internalAutoFlattenPaper(processed);
    if (DocumentEnhancementService.internalHasUnevenIllumination(processed)) {
      processed = DocumentEnhancementService
          .internalAutocorrectAntiLightShadows(processed);
    }
    processed =
        DocumentEnhancementService.internalAutoAdjustDarkImage(processed);
    return Uint8List.fromList(img.encodeJpg(processed, quality: 92));
  }

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  late img.Image processed;
  switch (filterName) {
    case 'lighten':
      processed = img.adjustColor(image, brightness: 1.2, contrast: 1.05);
    case 'enhance':
      processed = img.adjustColor(
        image,
        contrast: 1.25,
        saturation: 1.15,
        brightness: 1.05,
      );
    case 'eco':
      processed = img.adjustColor(
        img.grayscale(image),
        contrast: 1.15,
        brightness: 1.05,
      );
    case 'grayscale':
      processed = img.grayscale(image);
      processed = img.adjustColor(processed, contrast: 1.1);
    case 'invert':
      processed = img.invert(image);
    case 'sepia':
      processed = img.sepia(image);
      processed = img.adjustColor(processed, saturation: 0.85, brightness: 1.05);
    case 'warm':
      processed = img.adjustColor(
        image,
        saturation: 1.2,
        brightness: 1.04,
      );
      for (var y = 0; y < processed.height; y++) {
        for (var x = 0; x < processed.width; x++) {
          final p = processed.getPixel(x, y);
          final r = (p.r + 8).clamp(0, 255).toInt();
          final g = (p.g + 3).clamp(0, 255).toInt();
          final b = (p.b - 5).clamp(0, 255).toInt();
          processed.setPixelRgba(x, y, r, g, b, p.a.toInt());
        }
      }
    case 'cool':
      processed = img.adjustColor(
        image,
        saturation: 1.1,
        brightness: 1.03,
      );
      for (var y = 0; y < processed.height; y++) {
        for (var x = 0; x < processed.width; x++) {
          final p = processed.getPixel(x, y);
          final r = (p.r - 5).clamp(0, 255).toInt();
          final g = (p.g + 2).clamp(0, 255).toInt();
          final b = (p.b + 10).clamp(0, 255).toInt();
          processed.setPixelRgba(x, y, r, g, b, p.a.toInt());
        }
      }
    case 'dramatic':
      processed = img.adjustColor(
        image,
        contrast: 1.35,
        saturation: 0.8,
        brightness: 0.95,
      );
    case 'bwHighContrast':
      processed = _sauvolaBinarize(img.grayscale(image), window: 31, k: 0.28);
      processed = img.adjustColor(processed, contrast: 1.1);
    default:
      processed = image;
  }
  return Uint8List.fromList(img.encodeJpg(processed, quality: 92));
}

Uint8List? _isolateRotate90(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final rotated = img.copyRotate(image, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
}

Uint8List? _isolateRotate270(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final rotated = img.copyRotate(image, angle: -90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
}

class ImageFilterService {
  /// Fast, low-resolution preview used while the user browses enhancements.
  /// Full-resolution processing remains available through the methods below.
  static Future<ImageFilterResult?> applyPreview(
    Uint8List bytes,
    FilterType filterType,
  ) async {
    if (filterType == FilterType.none) return null;
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateApplyPreview({
        'bytes': bytes,
        'filter': filterType.name,
      });
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> applyFilter(
    Uint8List bytes,
    FilterType filterType,
  ) async {
    if (filterType == FilterType.none) return null;
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateApplyFilter({
        'bytes': bytes,
        'filter': filterType.name,
      });
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> applyMagicColor(Uint8List bytes) async {
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateApplyMagicColor({'bytes': bytes});
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> applyBinarization(Uint8List bytes) async {
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateApplyBinarization({'bytes': bytes});
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> applyShadowRemoval(Uint8List bytes) async {
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateApplyShadowRemoval({'bytes': bytes});
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> rotate90(Uint8List bytes) async {
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateRotate90({'bytes': bytes});
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<ImageFilterResult?> rotate270(Uint8List bytes) async {
    final result = await Isolate.run<Uint8List?>(() {
      return _isolateRotate270({'bytes': bytes});
    });
    if (result == null) return null;
    final decoded = img.decodeImage(result);
    if (decoded == null) return null;
    return ImageFilterResult(
      bytes: result,
      width: decoded.width,
      height: decoded.height,
    );
  }
}
