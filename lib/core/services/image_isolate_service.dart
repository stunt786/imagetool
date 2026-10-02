import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../utils/file_type_detector.dart';

/// Cheap metadata about an encoded image, obtained without a full decode.
@immutable
class ImageProbeResult {
  const ImageProbeResult({
    required this.width,
    required this.height,
    this.format,
    this.isValid = true,
  });

  const ImageProbeResult.invalid()
      : width = 0,
        height = 0,
        format = null,
        isValid = false;

  final int width;
  final int height;

  /// Canonical format name (`jpg`, `png`, ...) when detected.
  final String? format;

  final bool isValid;
}

/// Metadata and thumbnail resulting from a single decode pass.
@immutable
class ImageProbeAndThumbnailResult {
  const ImageProbeAndThumbnailResult({
    required this.width,
    required this.height,
    required this.format,
    required this.thumbnail,
  });

  const ImageProbeAndThumbnailResult.invalid()
      : width = 0,
        height = 0,
        format = '',
        thumbnail = null;

  final int width;
  final int height;
  final String format;
  final Uint8List? thumbnail;

  bool get isValid => width > 0 && height > 0;
}

/// Options for a decode -> (optional resize) -> encode round trip.
@immutable
class ImageTransformRequest {
  const ImageTransformRequest({
    required this.targetExtension,
    this.quality = 90,
    this.maxWidth,
    this.maxHeight,
    this.flattenAlpha = true,
    this.stripExif = true,
    this.backgroundColor = 0xFFFFFFFF,
  });

  /// `jpg`, `png`, `bmp`, `tiff` (webp is handled by [PlatformImageEncoder]).
  final String targetExtension;
  final int quality;
  final int? maxWidth;
  final int? maxHeight;
  final bool flattenAlpha;
  final bool stripExif;
  final int backgroundColor;
}

/// CPU-bound image work that is always executed off the UI isolate.
///
/// The heavy lifting (`img.decodeImage`, resizing, encoding) happens inside a
/// background isolate; only plain data crosses the isolate boundary.
abstract final class ImageIsolateService {
  /// Default number of images processed simultaneously. Keeps memory bounded
  /// on low-end devices while still using more than one core.
  static int get defaultConcurrency {
    var cores = 2;
    try {
      cores = Platform.numberOfProcessors;
    } catch (_) {
      // Fall back to the conservative default.
    }
    if (cores <= 2) return 2;
    if (cores <= 4) return 3;
    return 4;
  }

  /// Reads image dimensions and format from the header only.
  ///
  /// Much cheaper than a full decode, so it is safe to call for every picked
  /// file while the user is still selecting.
  static Future<ImageProbeResult> probe(Uint8List bytes) async {
    if (bytes.isEmpty) return const ImageProbeResult.invalid();
    try {
      final result = await compute(_probeWorker, bytes);
      return result ?? const ImageProbeResult.invalid();
    } catch (_) {
      return const ImageProbeResult.invalid();
    }
  }

  /// Probes many images with bounded concurrency, reporting real progress.
  static Future<List<ImageProbeResult>> probeAll(
    List<Uint8List> items, {
    int? concurrency,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return mapConcurrent<Uint8List, ImageProbeResult>(
      items,
      (bytes, _) => probe(bytes),
      concurrency: concurrency ?? defaultConcurrency,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ).then((results) => results
        .map((r) => r ?? const ImageProbeResult.invalid())
        .toList(growable: false));
  }

  /// Decodes, optionally downsizes and re-encodes [bytes] in an isolate.
  ///
  /// Returns null when the image cannot be decoded.
  static Future<Uint8List?> transform(
    Uint8List bytes,
    ImageTransformRequest request,
  ) async {
    if (bytes.isEmpty) return null;
    try {
      return await compute(_transformWorker, <String, Object?>{
        'bytes': bytes,
        'target': request.targetExtension,
        'quality': request.quality,
        'maxWidth': request.maxWidth,
        'maxHeight': request.maxHeight,
        'flattenAlpha': request.flattenAlpha,
        'stripExif': request.stripExif,
        'background': request.backgroundColor,
      });
    } catch (_) {
      return null;
    }
  }

  /// Produces a small preview for list/grid rendering.
  ///
  /// Never upscales and always flattens transparency so it can be encoded as
  /// JPEG for cheap caching.
  static Future<Uint8List?> thumbnail(
    Uint8List bytes, {
    int maxSide = 320,
    int quality = 78,
  }) {
    return transform(
      bytes,
      ImageTransformRequest(
        targetExtension: 'jpg',
        quality: quality,
        maxWidth: maxSide,
        maxHeight: maxSide,
      ),
    );
  }

  /// Decodes [bytes] once and returns both image metadata and a resized JPEG thumbnail,
  /// cutting decode overhead and memory usage in half.
  static Future<ImageProbeAndThumbnailResult> probeAndThumbnail(
    Uint8List bytes, {
    int maxSide = 320,
    int quality = 78,
  }) async {
    if (bytes.isEmpty) return const ImageProbeAndThumbnailResult.invalid();
    try {
      final result = await compute(_probeAndThumbnailWorker, <String, Object?>{
        'bytes': bytes,
        'maxSide': maxSide,
        'quality': quality,
      });
      return result ?? const ImageProbeAndThumbnailResult.invalid();
    } catch (_) {
      return const ImageProbeAndThumbnailResult.invalid();
    }
  }

  /// Runs [task] over [items] with at most [concurrency] tasks in flight.
  ///
  /// Results keep the input order. When [isCancelled] returns true the queue
  /// stops handing out new work and remaining results stay null.
  static Future<List<R?>> mapConcurrent<T, R>(
    List<T> items,
    Future<R?> Function(T item, int index) task, {
    int concurrency = 3,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = List<R?>.filled(items.length, null);
    if (items.isEmpty) {
      onProgress?.call(0, 0);
      return results;
    }

    var nextIndex = 0;
    var completed = 0;
    final workerCount =
        concurrency.clamp(1, items.isEmpty ? 1 : items.length);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final index = nextIndex++;
        if (index >= items.length) return;
        try {
          results[index] = await task(items[index], index);
        } catch (_) {
          results[index] = null;
        }
        completed++;
        onProgress?.call(completed, items.length);
      }
    }

    await Future.wait(List<Future<void>>.generate(workerCount, (_) => worker()));
    return results;
  }
}

// ─── Isolate entry points ───────────────────────────────────────────────────

ImageProbeResult? _probeWorker(Uint8List bytes) {
  final format = FileTypeDetector.imageFormatFromSignature(bytes);
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    return format == null
        ? const ImageProbeResult.invalid()
        : ImageProbeResult(width: 0, height: 0, format: format);
  }
  final info = decoder.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    return const ImageProbeResult.invalid();
  }
  return ImageProbeResult(
    width: info.width,
    height: info.height,
    format: format,
  );
}

Uint8List? _transformWorker(Map<String, Object?> params) {
  final bytes = params['bytes'] as Uint8List;
  final target = (params['target'] as String).toLowerCase();
  final quality = (params['quality'] as num?)?.toInt() ?? 90;
  final maxWidth = (params['maxWidth'] as num?)?.toInt();
  final maxHeight = (params['maxHeight'] as num?)?.toInt();
  final flattenAlpha = params['flattenAlpha'] as bool? ?? true;
  final stripExif = params['stripExif'] as bool? ?? true;
  final background = (params['background'] as num?)?.toInt() ?? 0xFFFFFFFF;

  var image = img.decodeImage(bytes);
  if (image == null) return null;

  if (stripExif) {
    try {
      image.exif.clear();
    } catch (_) {
      // Not all decoders carry EXIF data.
    }
  }

  image = _resizeIfNeeded(image, maxWidth, maxHeight);

  if (flattenAlpha &&
      image.hasAlpha &&
      (target == 'jpg' || target == 'jpeg' || target == 'bmp')) {
    image = _flattenAlpha(image, background);
  }

  final encoded = _encode(image, target, quality);
  return encoded == null ? null : Uint8List.fromList(encoded);
}

img.Image _resizeIfNeeded(img.Image image, int? maxWidth, int? maxHeight) {
  final width = maxWidth ?? 0;
  final height = maxHeight ?? 0;
  if (width <= 0 && height <= 0) return image;

  final scaleW = width > 0 ? width / image.width : double.infinity;
  final scaleH = height > 0 ? height / image.height : double.infinity;
  final scale = scaleW < scaleH ? scaleW : scaleH;
  if (!scale.isFinite || scale >= 1) return image;

  final targetWidth = (image.width * scale).round().clamp(1, image.width);
  final targetHeight = (image.height * scale).round().clamp(1, image.height);
  if (targetWidth == image.width && targetHeight == image.height) return image;

  return img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
}

img.Image _flattenAlpha(img.Image image, int backgroundArgb) {
  final flattened = img.Image(width: image.width, height: image.height);
  final r = (backgroundArgb >> 16) & 0xFF;
  final g = (backgroundArgb >> 8) & 0xFF;
  final b = backgroundArgb & 0xFF;
  img.fill(flattened, color: img.ColorRgb8(r, g, b));
  img.compositeImage(flattened, image);
  return flattened;
}

List<int>? _encode(img.Image image, String target, int quality) {
  switch (target) {
    case 'jpg':
    case 'jpeg':
      return img.encodeJpg(image, quality: quality.clamp(1, 100));
    case 'png':
      return img.encodePng(image);
    case 'bmp':
      return img.encodeBmp(image);
    case 'tif':
    case 'tiff':
      return img.encodeTiff(image);
    case 'webp':
      return img.encodeWebP(
        image,
        lossless: quality >= 100,
        quality: quality.clamp(1, 100),
      );
    default:
      return null;
  }
}

ImageProbeAndThumbnailResult? _probeAndThumbnailWorker(
  Map<String, Object?> params,
) {
  final bytes = params['bytes'] as Uint8List;
  final maxSide = (params['maxSide'] as num?)?.toInt() ?? 320;
  final quality = (params['quality'] as num?)?.toInt() ?? 78;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const ImageProbeAndThumbnailResult.invalid();

  final format = FileTypeDetector.imageFormatFromSignature(bytes) ?? 'jpg';
  final width = decoded.width;
  final height = decoded.height;

  var thumbImg = decoded;
  if (width > maxSide || height > maxSide) {
    thumbImg = img.copyResize(
      decoded,
      width: width >= height ? maxSide : null,
      height: height > width ? maxSide : null,
      interpolation: img.Interpolation.average,
    );
  }

  if (thumbImg.hasAlpha) {
    final flattened = img.Image(width: thumbImg.width, height: thumbImg.height);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, thumbImg);
    thumbImg = flattened;
  }

  final thumbBytes =
      Uint8List.fromList(img.encodeJpg(thumbImg, quality: quality));
  return ImageProbeAndThumbnailResult(
    width: width,
    height: height,
    format: format,
    thumbnail: thumbBytes,
  );
}
