import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/social_presets.dart';

class ImageProcessResult {
  const ImageProcessResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.fileSize,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int fileSize;
}

ImageProcessResult? _isolateResize(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  img.Image processed = image;

  if (width > 0 && height > 0) {
    final safeWidth = width.clamp(1, 12000);
    final safeHeight = height.clamp(1, 12000);

    processed = img.copyResize(
      image,
      width: safeWidth,
      height: safeHeight,
      interpolation: img.Interpolation.average,
    );
  }

  final encoded = _encodeImage(processed, format: format, quality: quality);
  final resultBytes = Uint8List.fromList(encoded);

  return ImageProcessResult(
    bytes: resultBytes,
    width: processed.width,
    height: processed.height,
    fileSize: resultBytes.length,
  );
}

ImageProcessResult? _isolateCrop(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final int x = params['x'] as int;
  final int y = params['y'] as int;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final safeX = x.clamp(0, math.max(0, image.width - 1)).toInt();
  final safeY = y.clamp(0, math.max(0, image.height - 1)).toInt();
  final safeWidth = width.clamp(1, image.width - safeX).toInt();
  final safeHeight = height.clamp(1, image.height - safeY).toInt();

  final cropped = img.copyCrop(
    image,
    x: safeX,
    y: safeY,
    width: safeWidth,
    height: safeHeight,
  );

  final encoded = _encodeImage(cropped, format: format, quality: quality);
  final resultBytes = Uint8List.fromList(encoded);

  return ImageProcessResult(
    bytes: resultBytes,
    width: cropped.width,
    height: cropped.height,
    fileSize: resultBytes.length,
  );
}

ImageProcessResult? _isolateRotate(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final double angle = params['angle'] as double;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final rotated = img.copyRotate(image, angle: angle);

  final encoded = _encodeImage(rotated, format: format, quality: quality);
  final resultBytes = Uint8List.fromList(encoded);

  return ImageProcessResult(
    bytes: resultBytes,
    width: rotated.width,
    height: rotated.height,
    fileSize: resultBytes.length,
  );
}

ImageProcessResult? _isolateFlip(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final bool horizontal = params['horizontal'] as bool;
  final bool vertical = params['vertical'] as bool;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  img.Image flipped = image;
  if (horizontal) {
    flipped = img.flipHorizontal(flipped);
  }
  if (vertical) {
    flipped = img.flipVertical(flipped);
  }

  final encoded = _encodeImage(flipped, format: format, quality: quality);
  final resultBytes = Uint8List.fromList(encoded);

  return ImageProcessResult(
    bytes: resultBytes,
    width: flipped.width,
    height: flipped.height,
    fileSize: resultBytes.length,
  );
}

ImageProcessResult? _isolateResizeToPreset(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final int targetWidth = params['targetWidth'] as int;
  final int targetHeight = params['targetHeight'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final sourceAspect = image.width / image.height;
  final targetAspect = targetWidth / targetHeight;

  img.Image processed;

  if (sourceAspect > targetAspect) {
    final newHeight = targetHeight;
    final newWidth = (targetHeight * sourceAspect).round();
    processed = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );
    final cropX = (newWidth - targetWidth) ~/ 2;
    processed = img.copyCrop(
      processed,
      x: cropX,
      y: 0,
      width: targetWidth,
      height: targetHeight,
    );
  } else {
    final newWidth = targetWidth;
    final newHeight = (targetWidth / sourceAspect).round();
    processed = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );
    final cropY = (newHeight - targetHeight) ~/ 2;
    processed = img.copyCrop(
      processed,
      x: 0,
      y: cropY,
      width: targetWidth,
      height: targetHeight,
    );
  }

  final encoded = _encodeImage(processed, format: format, quality: quality);
  final resultBytes = Uint8List.fromList(encoded);

  return ImageProcessResult(
    bytes: resultBytes,
    width: processed.width,
    height: processed.height,
    fileSize: resultBytes.length,
  );
}

ImageProcessResult? _isolateCompressToTargetSize(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final int targetBytes = params['targetBytes'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Never scale below this many pixels on the shortest side
  const int minDimension = 64;

  ImageProcessResult encodeAt(int targetWidth, int targetHeight, int quality) {
    final w = targetWidth.clamp(1, 12000);
    final h = targetHeight.clamp(1, 12000);
    final processed = img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: img.Interpolation.average,
    );
    final encoded = _encodeImage(processed, format: format, quality: quality);
    return ImageProcessResult(
      bytes: Uint8List.fromList(encoded),
      width: processed.width,
      height: processed.height,
      fileSize: encoded.length,
    );
  }

  // Tracks the best result that fits within the target budget
  ImageProcessResult? bestUnderTarget;

  void consider(ImageProcessResult r) {
    if (r.fileSize <= targetBytes) {
      if (bestUnderTarget == null || r.fileSize > bestUnderTarget!.fileSize) {
        bestUnderTarget = r;
      }
    }
  }

  // ––– Step 1: probe at full dimensions, medium quality –––
  final probe = encodeAt(image.width, image.height, 50);
  consider(probe);
  if (probe.fileSize <= targetBytes) {
    int low = 1;
    int high = 100;
    ImageProcessResult? best;
    while (low <= high) {
      final mid = ((low + high) / 2).round();
      final result = encodeAt(image.width, image.height, mid);
      consider(result);
      if (result.fileSize <= targetBytes) {
        best = result;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best ?? probe;
  }

  // ––– Step 2: iterative dimension + quality reduction –––
  double scale = (targetBytes / math.max(probe.fileSize, 1)).clamp(0.15, 1.0);

  for (int i = 0; i < 8; i++) {
    final int quality = math.max(15, 85 - i * 10);
    final int w = math.max(minDimension, (image.width * scale).round());
    final int h = math.max(minDimension, (image.height * scale).round());

    final result = encodeAt(w, h, quality);
    consider(result);

    if (result.fileSize <= targetBytes) {
      int qLow = quality;
      int qHigh = 100;
      ImageProcessResult? best;
      while (qLow <= qHigh) {
        final mid = ((qLow + qHigh) / 2).round();
        final r = encodeAt(w, h, mid);
        consider(r);
        if (r.fileSize <= targetBytes) {
          best = r;
          qLow = mid + 1;
        } else {
          qHigh = mid - 1;
        }
      }
      return best ?? result;
    }

    scale *= targetBytes / math.max(result.fileSize, 1);
    scale = scale.clamp(0.15, 1.0);
  }

  // ––– Step 3: return the best that fits, or a final reasonable attempt –––
  if (bestUnderTarget != null) return bestUnderTarget;

  return encodeAt(
    math.max(minDimension, image.width ~/ 4),
    math.max(minDimension, image.height ~/ 4),
    15,
  );
}

ImageProcessResult? _isolateDecodeInfo(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  return ImageProcessResult(
    bytes: bytes,
    width: image.width,
    height: image.height,
    fileSize: bytes.length,
  );
}

List<int> _encodeImage(
  img.Image image, {
  required OutputImageFormat format,
  required int quality,
}) {
  final clampedQuality = quality.clamp(1, 100);
  return switch (format) {
    OutputImageFormat.jpg => img.JpegEncoder(quality: clampedQuality).encode(image),
    OutputImageFormat.png => img.PngEncoder(level: ((100 - clampedQuality) / 11).round().clamp(0, 9)).encode(image),
    OutputImageFormat.webp => img.JpegEncoder(quality: clampedQuality).encode(image),
  };
}

class ImageProcessorService {
  static Future<ImageProcessResult?> resize({
    required Uint8List bytes,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateResize(<String, dynamic>{
        'bytes': bytes,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
      }),
    );
  }

  static Future<ImageProcessResult?> crop({
    required Uint8List bytes,
    required int x,
    required int y,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateCrop(<String, dynamic>{
        'bytes': bytes,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
      }),
    );
  }

  static Future<ImageProcessResult?> rotate({
    required Uint8List bytes,
    required double angle,
    required OutputImageFormat format,
    required int quality,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateRotate(<String, dynamic>{
        'bytes': bytes,
        'angle': angle,
        'format': format,
        'quality': quality,
      }),
    );
  }

  static Future<ImageProcessResult?> flip({
    required Uint8List bytes,
    required bool horizontal,
    required bool vertical,
    required OutputImageFormat format,
    required int quality,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateFlip(<String, dynamic>{
        'bytes': bytes,
        'horizontal': horizontal,
        'vertical': vertical,
        'format': format,
        'quality': quality,
      }),
    );
  }

  static Future<ImageProcessResult?> compressToTargetSize({
    required Uint8List bytes,
    required int targetBytes,
    required OutputImageFormat format,
    void Function(double progress)? onProgress,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateCompressToTargetSize(<String, dynamic>{
        'bytes': bytes,
        'targetBytes': targetBytes,
        'format': format,
      }),
    );
  }

  static Future<ImageProcessResult?> resizeToPreset({
    required Uint8List bytes,
    required SocialPreset preset,
    required OutputImageFormat format,
    required int quality,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateResizeToPreset(<String, dynamic>{
        'bytes': bytes,
        'targetWidth': preset.width,
        'targetHeight': preset.height,
        'format': format,
        'quality': quality,
      }),
    );
  }

  static Future<ImageProcessResult?> decodeImageInfo(Uint8List bytes) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateDecodeInfo(<String, dynamic>{
        'bytes': bytes,
      }),
    );
  }
}
