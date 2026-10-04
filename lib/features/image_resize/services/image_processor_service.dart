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
  final SendPort? sendPort = params['sendPort'] as SendPort?;

  sendPort?.send(0.12);
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  sendPort?.send(0.35);

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

    if (newWidth != image.width || newHeight != image.height) {
      processed = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    }
  }

  sendPort?.send(0.70);

  final encoded = _encodeImage(processed,
      format: format, quality: quality, settings: settings);
  final resultBytes = Uint8List.fromList(encoded);

  sendPort?.send(1.0);
  sendPort?.send('done');

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
  final SendPort? sendPort = params['sendPort'] as SendPort?;

  sendPort?.send(0.12);
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  sendPort?.send(0.40);

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

  sendPort?.send(0.70);

  final encoded = _encodeImage(cropped,
      format: format, quality: quality, settings: settings);
  final resultBytes = Uint8List.fromList(encoded);

  sendPort?.send(1.0);
  sendPort?.send('done');

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
  final SendPort? sendPort = params['sendPort'] as SendPort?;

  sendPort?.send(0.12);
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  sendPort?.send(0.40);

  final rotated = img.copyRotate(image, angle: angle);

  sendPort?.send(0.70);

  final encoded = _encodeImage(rotated,
      format: format, quality: quality, settings: settings);
  final resultBytes = Uint8List.fromList(encoded);

  sendPort?.send(1.0);
  sendPort?.send('done');

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
  final SendPort? sendPort = params['sendPort'] as SendPort?;

  sendPort?.send(0.12);
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  sendPort?.send(0.40);

  img.Image flipped = image;
  if (horizontal) {
    flipped = img.flipHorizontal(flipped);
  }
  if (vertical) {
    flipped = img.flipVertical(flipped);
  }

  sendPort?.send(0.70);

  final encoded = _encodeImage(flipped,
      format: format, quality: quality, settings: settings);
  final resultBytes = Uint8List.fromList(encoded);

  sendPort?.send(1.0);
  sendPort?.send('done');

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
  final SendPort? sendPort = params['sendPort'] as SendPort?;

  sendPort?.send(0.12);
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  sendPort?.send(0.35);

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
      interpolation: img.Interpolation.linear,
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
      interpolation: img.Interpolation.linear,
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

  sendPort?.send(0.70);

  final encoded = _encodeImage(processed,
      format: format, quality: quality, settings: settings);
  final resultBytes = Uint8List.fromList(encoded);

  sendPort?.send(1.0);
  sendPort?.send('done');

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
  // Safety margin: keep the file strictly below target size by a few KB (not higher).
  // Scaled margin so e.g. 100 KB has ~3.5 KB margin, 500 KB has ~16 KB margin.
  final int safetyMargin =
      math.max(3072, (targetBytes * 0.035).round().clamp(3072, 16384));
  final int budgetBytes = math.max(1024, targetBytes - safetyMargin);
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final SendPort? sendPort = params['sendPort'] as SendPort?;
  final AppSettingsState? settings = params['settings'] as AppSettingsState?;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  final origW = image.width;
  final origH = image.height;

  final Map<String, ImageProcessResult> cache = <String, ImageProcessResult>{};
  final Map<String, img.Image> resizedCache = <String, img.Image>{};

  img.Image getResized(int w, int h) {
    if (w == origW && h == origH) return image;
    final key = '$w:$h';
    return resizedCache.putIfAbsent(
      key,
      () => img.copyResize(
        image,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      ),
    );
  }

  ImageProcessResult encodeAt(int targetWidth, int targetHeight, int quality) {
    final w = targetWidth.clamp(1, 12000);
    final h = targetHeight.clamp(1, 12000);
    final q = quality.clamp(1, 100);
    final cacheKey = '$w:$h:$q';
    final cached = cache[cacheKey];
    if (cached != null) return cached;

    final processed = getResized(w, h);
    final encoded = _encodeImage(processed,
        format: format, quality: q, settings: settings);
    final result = ImageProcessResult(
      bytes: Uint8List.fromList(encoded),
      width: processed.width,
      height: processed.height,
      fileSize: encoded.length,
    );
    cache[cacheKey] = result;
    return result;
  }

  // Tracks the best result that fits strictly within the target budget, plus the
  // closest overshoot in case nothing fits the budget.
  ImageProcessResult? bestUnderTarget;
  ImageProcessResult? smallestOver;

  void consider(ImageProcessResult r) {
    if (r.fileSize <= budgetBytes) {
      if (bestUnderTarget == null || r.fileSize > bestUnderTarget!.fileSize) {
        bestUnderTarget = r;
      }
    } else if (r.fileSize <= targetBytes && bestUnderTarget == null) {
      bestUnderTarget = r;
    } else if (smallestOver == null || r.fileSize < smallestOver!.fileSize) {
      smallestOver = r;
    }
  }

  void reportProgress(double progress) {
    sendPort?.send(progress);
  }

  // ── Step 1: Probe full dimensions at high quality (85) ──
  reportProgress(0.08);
  final probeHigh = encodeAt(origW, origH, 85);
  consider(probeHigh);

  if (probeHigh.fileSize <= budgetBytes) {
    // Already fits at full dimensions! Try raising quality up to 100 to get as close as possible.
    int qLow = 86;
    int qHigh = 100;
    while (qLow <= qHigh) {
      final mid = (qLow + qHigh) ~/ 2;
      final r = encodeAt(origW, origH, mid);
      consider(r);
      if (r.fileSize <= budgetBytes) {
        qLow = mid + 1;
      } else {
        qHigh = mid - 1;
      }
    }
    reportProgress(1.0);
    sendPort?.send('done');
    return bestUnderTarget ?? probeHigh;
  }

  // ── Step 2: Probe full dimensions at medium quality (60) ──
  reportProgress(0.20);
  final probeMed = encodeAt(origW, origH, 60);
  consider(probeMed);

  if (probeMed.fileSize <= budgetBytes) {
    // Full dimensions fit if quality is between 60 and 84!
    int qLow = 61;
    int qHigh = 84;
    while (qLow <= qHigh) {
      final mid = (qLow + qHigh) ~/ 2;
      final r = encodeAt(origW, origH, mid);
      consider(r);
      if (r.fileSize <= budgetBytes) {
        qLow = mid + 1;
      } else {
        qHigh = mid - 1;
      }
    }
    reportProgress(1.0);
    sendPort?.send('done');
    return bestUnderTarget ?? probeMed;
  }

  // ── Step 3: Full dimensions exceed budget even at Q=60.
  // We must resize dimensions!
  // Binary search for dimension scale `s` in [0.02, 1.0] at base quality 80.
  final double estScale = (math.sqrt(budgetBytes / math.max(probeMed.fileSize, 1)) *
          math.sqrt(60.0 / 80.0))
      .clamp(0.03, 0.98);

  double lowScale = 0.02;
  double highScale = 1.0;

  // First test the estimated scale
  final firstRes = encodeAt(
    math.max(16, (origW * estScale).round()),
    math.max(16, (origH * estScale).round()),
    80,
  );
  consider(firstRes);
  if (firstRes.fileSize <= budgetBytes) {
    lowScale = estScale;
  } else {
    highScale = estScale;
  }

  // Refine scale with 7 binary search iterations
  for (int i = 0; i < 7; i++) {
    reportProgress(0.30 + (i / 7) * 0.45);
    final midScale = (lowScale + highScale) / 2;
    final w = math.max(16, (origW * midScale).round());
    final h = math.max(16, (origH * midScale).round());
    final res = encodeAt(w, h, 80);
    consider(res);
    if (res.fileSize <= budgetBytes) {
      lowScale = midScale;
    } else {
      highScale = midScale;
    }
  }

  // ── Step 4: Fine-tune quality at the optimal dimensions ──
  // If the best result under budget is a bit below budgetBytes, bump quality
  // upwards to get right up to the few-KB-below target threshold.
  if (bestUnderTarget != null) {
    final bestW = bestUnderTarget!.width;
    final bestH = bestUnderTarget!.height;
    int qLow = 81;
    int qHigh = 98;
    while (qLow <= qHigh) {
      final midQ = (qLow + qHigh) ~/ 2;
      final res = encodeAt(bestW, bestH, midQ);
      consider(res);
      if (res.fileSize <= budgetBytes) {
        qLow = midQ + 1;
      } else {
        qHigh = midQ - 1;
      }
    }
  }

  // ── Step 5: Fallback if bestUnderTarget is still null (extremely tiny target) ──
  if (bestUnderTarget == null) {
    for (double s = 0.05; s >= 0.01 && bestUnderTarget == null; s /= 2) {
      for (int q = 50; q >= 10 && bestUnderTarget == null; q -= 15) {
        final w = math.max(8, (origW * s).round());
        final h = math.max(8, (origH * s).round());
        final res = encodeAt(w, h, q);
        consider(res);
      }
    }
  }

  reportProgress(1.0);
  sendPort?.send('done');

  if (bestUnderTarget != null && bestUnderTarget!.fileSize <= targetBytes) {
    return bestUnderTarget;
  }
  if (smallestOver != null && smallestOver!.fileSize <= targetBytes) {
    return smallestOver;
  }

  // Absolute fallback: tiny low quality image strictly under target
  for (int dim = 64; dim >= 8; dim ~/= 2) {
    final lastAttempt = encodeAt(dim, dim, 5);
    if (lastAttempt.fileSize <= targetBytes) {
      return lastAttempt;
    }
  }

  return bestUnderTarget ?? smallestOver ?? probeHigh;
}

ImageProcessResult? _isolateResizeEstimate(Map<String, dynamic> params) {
  final Uint8List bytes = params['bytes'] as Uint8List;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(bytes);
  if (image == null) return null;

  // Fast live estimate: downscale a proxy with linear interpolation and
  // encode without watermark/EXIF work. Keeps typing/slider at 60fps while
  // the final apply still uses the high-quality path.
  const maxProxy = 800;
  final scale = math.min(1.0, maxProxy / math.max(image.width, image.height));
  img.Image proxy = image;
  if (scale < 1.0) {
    proxy = img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
  }
  final safeWidth = width.clamp(1, 12000);
  final safeHeight = height.clamp(1, 12000);
  final resized = img.copyResize(
    proxy,
    width: (safeWidth * scale).clamp(1, 12000).round(),
    height: (safeHeight * scale).clamp(1, 12000).round(),
    interpolation: img.Interpolation.linear,
  );
  final clampedQuality = quality.clamp(1, 100);
  final encoded = switch (format) {
    OutputImageFormat.jpg =>
      img.JpegEncoder(quality: clampedQuality).encode(resized),
    OutputImageFormat.png => img.PngEncoder(
        level: ((100 - clampedQuality) / 11).round().clamp(0, 9),
      ).encode(resized),
    OutputImageFormat.webp => img.PngEncoder(
        level: ((100 - clampedQuality) / 11).round().clamp(0, 9),
      ).encode(resized),
  };
  // Scale the proxy byte count back up so the displayed estimate tracks the
  // full-resolution output instead of the proxy size.
  final estimated = (encoded.length / math.max(scale, 0.05)).round();
  return ImageProcessResult(
    bytes: Uint8List.fromList(encoded),
    width: safeWidth,
    height: safeHeight,
    fileSize: estimated,
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
      img.PngEncoder(level: ((100 - clampedQuality) / 16).round().clamp(0, 6))
          .encode(processed),
    OutputImageFormat.webp => img.encodeWebP(
        processed,
        lossless: clampedQuality >= 100,
        quality: clampedQuality,
      ),
  };
}

class ImageProcessorService {
  static Future<ImageProcessResult?> _dispatchToIsolate(
    ImageProcessResult? Function(Map<String, dynamic>) isolateFn,
    Map<String, dynamic> params,
  ) {
    return Isolate.run<ImageProcessResult?>(() => isolateFn(params));
  }

  static Future<ImageProcessResult?> _runWithProgress(
    Map<String, dynamic> params,
    ImageProcessResult? Function(Map<String, dynamic>) isolateFn,
    void Function(double progress)? onProgress,
  ) async {
    if (onProgress == null) {
      return _dispatchToIsolate(isolateFn, params);
    }
    final receivePort = ReceivePort();
    final sendPort = receivePort.sendPort;
    final progressCompleter = Completer<void>();
    final progressSub = receivePort.listen((message) {
      if (message is double) {
        onProgress(message);
      } else if (message == 'done') {
        if (!progressCompleter.isCompleted) {
          progressCompleter.complete();
        }
      }
    });
    try {
      final updatedParams = Map<String, dynamic>.from(params);
      updatedParams['sendPort'] = sendPort;
      final result = await _dispatchToIsolate(isolateFn, updatedParams);
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

  static Future<ImageProcessResult?> resize({
    required Uint8List bytes,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    bool preserveAspectRatio = true,
    void Function(double progress)? onProgress,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
        'settings': settings,
        'preserveAspectRatio': preserveAspectRatio,
      },
      _isolateResize,
      onProgress,
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
    void Function(double progress)? onProgress,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
        'settings': settings,
      },
      _isolateCrop,
      onProgress,
    );
  }

  static Future<ImageProcessResult?> rotate({
    required Uint8List bytes,
    required double angle,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'angle': angle,
        'format': format,
        'quality': quality,
        'settings': settings,
      },
      _isolateRotate,
      onProgress,
    );
  }

  static Future<ImageProcessResult?> flip({
    required Uint8List bytes,
    required bool horizontal,
    required bool vertical,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'horizontal': horizontal,
        'vertical': vertical,
        'format': format,
        'quality': quality,
        'settings': settings,
      },
      _isolateFlip,
      onProgress,
    );
  }

  static Future<ImageProcessResult?> compressToTargetSize({
    required Uint8List bytes,
    required int targetBytes,
    required OutputImageFormat format,
    void Function(double progress)? onProgress,
    AppSettingsState? settings,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'targetBytes': targetBytes,
        'format': format,
        'settings': settings,
      },
      _isolateCompressToTargetSize,
      onProgress,
    );
  }

  static Future<ImageProcessResult?> resizeToPreset({
    required Uint8List bytes,
    required SocialPreset preset,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    return _runWithProgress(
      <String, dynamic>{
        'bytes': bytes,
        'targetWidth': preset.width,
        'targetHeight': preset.height,
        'format': format,
        'quality': quality,
        'settings': settings,
      },
      _isolateResizeToPreset,
      onProgress,
    );
  }

  static Future<ImageProcessResult?> decodeImageInfo(Uint8List bytes) async {
    return Isolate.run<ImageProcessResult?>(
      () => _isolateDecodeInfo(<String, dynamic>{
        'bytes': bytes,
      }),
    );
  }

  /// Fast live estimate for the Est. size row: linear interpolation on a
  /// downscaled proxy, no watermark/EXIF work. The final apply path keeps
  /// the high-quality encoder.
  static Future<int?> estimateResizeBytes({
    required Uint8List bytes,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final result = await Isolate.run<ImageProcessResult?>(
      () => _isolateResizeEstimate(<String, dynamic>{
        'bytes': bytes,
        'width': width,
        'height': height,
        'format': format,
        'quality': quality,
      }),
    );
    return result?.fileSize;
  }

  static Future<int?> estimatePresetBytes({
    required Uint8List bytes,
    required int targetWidth,
    required int targetHeight,
    required OutputImageFormat format,
    required int quality,
  }) async {
    // Preset apply uses cover-resize + center-crop, so estimate with the
    // same worker instead of plain resize to avoid estimate/output mismatch.
    final result = await Isolate.run<ImageProcessResult?>(
      () => _isolateResizeToPreset(<String, dynamic>{
        'bytes': bytes,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
        'format': format,
        'quality': quality,
      }),
    );
    return result?.fileSize;
  }
}
