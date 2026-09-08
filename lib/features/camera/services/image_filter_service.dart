import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/scanned_page.dart';

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
  // Increase contrast
  processed = img.adjustColor(processed, contrast: 1.3, saturation: 1.2);
  // Sharpen slightly
  processed = img.gaussianBlur(processed, radius: 1);

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
  var maxVariance = 0.0;
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
    if (between >= maxVariance) {
      maxVariance = between;
      threshold = i;
    }
  }

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

  img.Image processed = img.grayscale(image);

  // Apply large blur to extract background illumination
  final kernelSize = math.max(processed.width, processed.height) ~/ 8;
  final blurred = img.gaussianBlur(processed, radius: kernelSize.clamp(3, 99));

  // Subtract background and normalize
  for (var y = 0; y < processed.height; y++) {
    for (var x = 0; x < processed.width; x++) {
      final origPixel = processed.getPixel(x, y);
      final bgPixel = blurred.getPixel(x, y);
      var diff = origPixel.r.toInt() - bgPixel.r.toInt();
      diff = ((diff + 255) * 128 ~/ 255).clamp(0, 255);
      processed.setPixelRgba(x, y, diff, diff, diff, 255);
    }
  }

  // Stretch contrast
  processed = img.adjustColor(processed, contrast: 1.4);

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

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  late img.Image processed;
  switch (filterName) {
    case 'lighten':
      processed = img.adjustColor(image, brightness: 0.18);
    case 'enhance':
      processed = img.adjustColor(
        image,
        contrast: 1.35,
        saturation: 1.12,
        brightness: 0.06,
      );
    case 'eco':
      processed = img.adjustColor(
        img.grayscale(image),
        contrast: 1.12,
        brightness: 0.04,
      );
    case 'grayscale':
      processed = img.grayscale(image);
    case 'invert':
      processed = img.invert(image);
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
