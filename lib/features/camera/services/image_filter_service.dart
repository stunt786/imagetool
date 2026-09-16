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

  img.Image processed = image;
  processed = img.adjustColor(processed, contrast: 1.25, saturation: 1.2, brightness: 1.05);

  return Uint8List.fromList(img.encodeJpg(processed, quality: 92));
}

Uint8List? _isolateApplyBinarization(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  img.Image processed = img.grayscale(image);

  // Otsu's thresholding
  final histogram = List.filled(256, 0);
  for (var y = 0; y < processed.height; y++) {
    for (var x = 0; x < processed.width; x++) {
      final pixel = processed.getPixel(x, y);
      final l = pixel.r.toInt();
      histogram[l.clamp(0, 255)]++;
    }
  }

  var total = processed.width * processed.height;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }

  var sumB = 0.0;
  var wB = 0;
  var wF = 0;
  var maxVariance = -1.0;
  var threshold = 128;

  for (var i = 0; i < 256; i++) {
    wB += histogram[i];
    if (wB == 0) continue;
    wF = total - wB;
    if (wF == 0) break;
    sumB += i * histogram[i];
    var mB = sumB / wB;
    var mF = (sum - sumB) / wF;
    var between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
    if (between > maxVariance) {
      maxVariance = between;
      threshold = i;
    }
  }

  threshold = threshold.clamp(40, 220);

  for (var y = 0; y < processed.height; y++) {
    for (var x = 0; x < processed.width; x++) {
      final pixel = processed.getPixel(x, y);
      final intensity = pixel.r;
      if (intensity > threshold) {
        processed.setPixelRgba(x, y, 255, 255, 255, 255);
      } else {
        processed.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(processed, quality: 95));
}

Uint8List? _isolateApplyShadowRemoval(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final gray = img.grayscale(image);

  // Fast illumination estimation via downsampled blur
  const bgDim = 64;
  final smallW = math.max(16, gray.width ~/ bgDim);
  final smallH = math.max(16, gray.height ~/ bgDim);
  final small = img.copyResize(gray, width: smallW, height: smallH);
  final blurredSmall = img.gaussianBlur(small, radius: 4);
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
    var processed = DocumentEnhancementService.internalAutoFitPaper(image);
    processed = DocumentEnhancementService.internalAutoFlattenPaper(processed);
    processed = DocumentEnhancementService.internalAutocorrectAntiLightShadows(processed);
    processed = DocumentEnhancementService.internalAutoAdjustDarkImage(processed);
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
      processed = img.grayscale(image);
      final histogram = List.filled(256, 0);
      for (var y = 0; y < processed.height; y++) {
        for (var x = 0; x < processed.width; x++) {
          final l = processed.getPixel(x, y).r.toInt();
          histogram[l.clamp(0, 255)]++;
        }
      }
      var total = processed.width * processed.height;
      var sum = 0.0;
      for (var i = 0; i < 256; i++) {
        sum += i * histogram[i];
      }
      var sumB = 0.0;
      var wB = 0;
      var maxVariance = -1.0;
      var threshold = 128;
      for (var i = 0; i < 256; i++) {
        wB += histogram[i];
        if (wB == 0) continue;
        final wF = total - wB;
        if (wF == 0) break;
        sumB += i * histogram[i];
        final mB = sumB / wB;
        final mF = (sum - sumB) / wF;
        final between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
        if (between > maxVariance) {
          maxVariance = between;
          threshold = i;
        }
      }
      threshold = threshold.clamp(40, 220);
      for (var y = 0; y < processed.height; y++) {
        for (var x = 0; x < processed.width; x++) {
          final intensity = processed.getPixel(x, y).r;
          if (intensity > threshold) {
            processed.setPixelRgba(x, y, 255, 255, 255, 255);
          } else {
            processed.setPixelRgba(x, y, 0, 0, 0, 255);
          }
        }
      }
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
