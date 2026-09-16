import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/settings/app_settings.dart';
import '../../../shared/services/watermark_helper.dart';
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
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;
  final bool preserveAspectRatio =
      params['preserveAspectRatio'] as bool? ?? true;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  img.Image processed = image;

  if (width > 0 && height > 0) {
    final safeWidth = width.clamp(1, 12000);
    final safeHeight = height.clamp(1, 12000);

    int newWidth = safeWidth;
    int newHeight = safeHeight;
    if (preserveAspectRatio) {
      final sourceAspect = image.width / image.height;
      final targetAspect = safeWidth / safeHeight;
      if (sourceAspect > targetAspect) {
        newHeight = (safeWidth / sourceAspect).round().clamp(1, 12000);
      } else {
        newWidth = (safeHeight * sourceAspect).round().clamp(1, 12000);
      }
    }

    processed = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.average,
    );
  }

  final encoded = _encodeImage(processed,
      format: format, quality: quality, settings: settings);
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
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

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

  final encoded = _encodeImage(cropped,
      format: format, quality: quality, settings: settings);
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
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final rotated = img.copyRotate(image, angle: angle);

  final encoded = _encodeImage(rotated,
      format: format, quality: quality, settings: settings);
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
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  img.Image flipped = image;
  if (horizontal) {
    flipped = img.flipHorizontal(flipped);
  }
  if (vertical) {
    flipped = img.flipVertical(flipped);
  }

  final encoded = _encodeImage(flipped,
      format: format, quality: quality, settings: settings);
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
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

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

  final encoded = _encodeImage(processed,
      format: format, quality: quality, settings: settings);
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
  // Leave a small safety margin so a user selecting 100 KB receives a file
  // below the displayed target rather than one that rounds above it.
  final int budgetBytes = math.max(1, (targetBytes * 0.99).floor());
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final SendPort? sendPort = params['sendPort'] as SendPort?;
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  ImageProcessResult encodeAt(int targetWidth, int targetHeight, int quality) {
    final w = targetWidth.clamp(1, 12000);
    final h = targetHeight.clamp(1, 12000);
    final processed = img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: img.Interpolation.average,
    );
    final encoded = _encodeImage(processed,
        format: format, quality: quality, settings: settings);
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
    if (r.fileSize <= budgetBytes) {
      if (bestUnderTarget == null || r.fileSize > bestUnderTarget!.fileSize) {
        bestUnderTarget = r;
      }
    }
  }

  void reportProgress(double progress) {
    sendPort?.send(progress);
  }

  // ––– Step 1: probe at full dimensions, medium quality –––
  reportProgress(0.05);
  final probe = encodeAt(image.width, image.height, 50);
  consider(probe);
  reportProgress(0.15);
  if (probe.fileSize <= budgetBytes) {
    int low = 1;
    int high = 100;
    ImageProcessResult? best;
    double searchProgress = 0.15;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final result = encodeAt(image.width, image.height, mid);
      consider(result);
      searchProgress += 0.05;
      reportProgress(searchProgress.clamp(0.15, 0.45));
      if (result.fileSize <= budgetBytes) {
        best = result;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    reportProgress(1.0);
    sendPort?.send('done');
    return best ?? probe;
  }

  // ––– Step 2: iterative dimension + quality reduction –––
  double scale = (budgetBytes / math.max(probe.fileSize, 1)).clamp(0.05, 1.0);

  for (int i = 0; i < 10; i++) {
    final int quality = math.max(10, 85 - i * 8);
    final int w = math.max(16, (image.width * scale).round());
    final int h = math.max(16, (image.height * scale).round());

    final result = encodeAt(w, h, quality);
    consider(result);
    reportProgress(0.45 + (i + 1) * 0.05);

    if (result.fileSize <= budgetBytes) {
      int qLow = quality;
      int qHigh = 100;
      while (qLow <= qHigh) {
        final mid = (qLow + qHigh) ~/ 2;
        final r = encodeAt(w, h, mid);
        consider(r);
        if (r.fileSize <= budgetBytes) {
          qLow = mid + 1;
        } else {
          qHigh = mid - 1;
        }
      }
      break;
    }

    scale *= math.sqrt(budgetBytes / math.max(result.fileSize, 1));
    scale = scale.clamp(0.02, 1.0);
  }

  // ––– Step 3: aggressive fallback loop if still over targetBytes –––
  if (bestUnderTarget == null) {
    double fallbackScale = 0.5;
    int q = 30;
    while (fallbackScale >= 0.02 && bestUnderTarget == null) {
      final w = math.max(16, (image.width * fallbackScale).round());
      final h = math.max(16, (image.height * fallbackScale).round());
      final attempt = encodeAt(w, h, q);
      consider(attempt);
      if (attempt.fileSize <= budgetBytes) {
        break;
      }
      if (q > 5) {
        q = math.max(5, q - 10);
      } else {
        fallbackScale *= 0.6;
      }
    }
  }

  reportProgress(1.0);
  sendPort?.send('done');
  if (bestUnderTarget != null && bestUnderTarget!.fileSize <= budgetBytes) {
    return bestUnderTarget;
  }

  // Absolute fallback: tiny low quality image strictly under target
  for (int dim = 64; dim >= 8; dim ~/= 2) {
    final lastAttempt = encodeAt(dim, dim, 5);
    if (lastAttempt.fileSize <= budgetBytes) {
      return lastAttempt;
    }
  }

  return bestUnderTarget ?? probe;
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
  bool stripExif = true,
  AppSettingsState? settings,
}) {
  var processed = image;
  if (settings != null && settings.enableGlobalWatermark) {
    processed = WatermarkHelper.applyToImage(processed, settings);
  }
  if (stripExif) {
    processed.exif.clear();
  }
  final clampedQuality = quality.clamp(1, 100);
  return switch (format) {
    OutputImageFormat.jpg =>
      img.JpegEncoder(quality: clampedQuality).encode(processed),
    OutputImageFormat.png =>
      img.PngEncoder(level: ((100 - clampedQuality) / 11).round().clamp(0, 9))
          .encode(processed),
    // image currently supplies a WebP decoder only. Preserve the existing
    // lossless fallback for cross-platform exports.
    OutputImageFormat.webp =>
      img.PngEncoder(level: ((100 - clampedQuality) / 11).round().clamp(0, 9))
          .encode(processed),
  };
}

class ImageProcessorService {
  static Future<ImageProcessResult?> resize({
    required Uint8List bytes,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    bool preserveAspectRatio = true,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateResize(<String, dynamic>{
        'bytes': bytes,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
        'settings': settings,
        'preserveAspectRatio': preserveAspectRatio,
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
    AppSettingsState? settings,
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
        'settings': settings,
      }),
    );
  }

  static Future<ImageProcessResult?> rotate({
    required Uint8List bytes,
    required double angle,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateRotate(<String, dynamic>{
        'bytes': bytes,
        'angle': angle,
        'format': format,
        'quality': quality,
        'settings': settings,
      }),
    );
  }

  static Future<ImageProcessResult?> flip({
    required Uint8List bytes,
    required bool horizontal,
    required bool vertical,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateFlip(<String, dynamic>{
        'bytes': bytes,
        'horizontal': horizontal,
        'vertical': vertical,
        'format': format,
        'quality': quality,
        'settings': settings,
      }),
    );
  }

  static Future<ImageProcessResult?> compressToTargetSize({
    required Uint8List bytes,
    required int targetBytes,
    required OutputImageFormat format,
    void Function(double progress)? onProgress,
    AppSettingsState? settings,
  }) async {
    if (onProgress == null) {
      return Isolate.run<ImageProcessResult?>(
        () => _isolateCompressToTargetSize(<String, dynamic>{
          'bytes': bytes,
          'targetBytes': targetBytes,
          'format': format,
          'settings': settings,
        }),
      );
    }
    final receivePort = ReceivePort();
    final sendPort = receivePort.sendPort;
    final progressCompleter = Completer<void>();
    final progressSub = receivePort.listen((message) {
      if (message is double) {
        onProgress(message);
      } else if (message == 'done') {
        progressCompleter.complete();
      }
    });
    try {
      final result = await Isolate.run<ImageProcessResult?>(
        () => _isolateCompressToTargetSize(<String, dynamic>{
          'bytes': bytes,
          'targetBytes': targetBytes,
          'format': format,
          'sendPort': sendPort,
          'settings': settings,
        }),
      );
      return result;
    } finally {
      await progressCompleter.future.timeout(
        const Duration(milliseconds: 50),
        onTimeout: () {},
      );
      await progressSub.cancel();
      receivePort.close();
    }
  }

  static Future<ImageProcessResult?> resizeToPreset({
    required Uint8List bytes,
    required SocialPreset preset,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
  }) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateResizeToPreset(<String, dynamic>{
        'bytes': bytes,
        'targetWidth': preset.width,
        'targetHeight': preset.height,
        'format': format,
        'quality': quality,
        'settings': settings,
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
