import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../features/image_resize/models/social_presets.dart';
import '../../features/image_resize/services/image_processor_service.dart';

enum WatermarkPosition {
  bottomRight('Bottom-Right'),
  center('Center'),
  topLeft('Top-Left'),
  bottomLeft('Bottom-Left'),
  topRight('Top-Right');

  const WatermarkPosition(this.label);
  final String label;
}

enum WatermarkTextSize {
  small('Small', 0.03),
  medium('Medium', 0.05),
  large('Large', 0.08),
  extraLarge('Extra Large', 0.12);

  const WatermarkTextSize(this.label, this.scaleFactor);
  final String label;
  final double scaleFactor;
}

img.Image? _decodeNormalizedImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return img.bakeOrientation(decoded);
}

Map<String, int>? _isolateDecodeDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  return {'width': oriented.width, 'height': oriented.height};
}

class ImageEditState {
  const ImageEditState({
    this.originalBytes,
    this.currentBytes,
    this.fileName,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  final Uint8List? originalBytes;
  final Uint8List? currentBytes;
  final String? fileName;
  final int width;
  final int height;
  final int fileSize;
  final bool isLoading;
  final String? errorMessage;

  bool get hasImage => currentBytes != null;

  ImageEditState copyWith({
    Uint8List? originalBytes,
    Uint8List? currentBytes,
    String? fileName,
    int? width,
    int? height,
    int? fileSize,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ImageEditState(
      originalBytes: originalBytes ?? this.originalBytes,
      currentBytes: currentBytes ?? this.currentBytes,
      fileName: fileName ?? this.fileName,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage,
    );
  }
}

class ResizeResult {
  const ResizeResult({
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

ResizeResult? _isolateResize(Map<String, dynamic> params) {
  final Uint8List sourceBytes = params['bytes'] as Uint8List;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = img.decodeImage(sourceBytes);
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

  final bytes = Uint8List.fromList(
    _encodeImage(processed, format: format, quality: quality),
  );

  return ResizeResult(
    bytes: bytes,
    width: processed.width,
    height: processed.height,
    fileSize: bytes.length,
  );
}

ResizeResult? _isolateCrop(Map<String, dynamic> params) {
  final Uint8List sourceBytes = params['bytes'] as Uint8List;
  final int x = params['x'] as int;
  final int y = params['y'] as int;
  final int width = params['width'] as int;
  final int height = params['height'] as int;

  final image = _decodeNormalizedImage(sourceBytes);
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
  final format = params['format'] as OutputImageFormat? ?? OutputImageFormat.jpg;
  final quality = params['quality'] as int? ?? 95;
  final bytes = Uint8List.fromList(
    _encodeImage(cropped, format: format, quality: quality),
  );

  return ResizeResult(
    bytes: bytes,
    width: cropped.width,
    height: cropped.height,
    fileSize: bytes.length,
  );
}

ResizeResult? _isolateRotate(Map<String, dynamic> params) {
  final Uint8List sourceBytes = params['bytes'] as Uint8List;
  final double angle = params['angle'] as double;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = _decodeNormalizedImage(sourceBytes);
  if (image == null) return null;

  final rotated = img.copyRotate(image, angle: angle);
  final bytes = Uint8List.fromList(
    _encodeImage(rotated, format: format, quality: quality),
  );

  return ResizeResult(
    bytes: bytes,
    width: rotated.width,
    height: rotated.height,
    fileSize: bytes.length,
  );
}

ResizeResult? _isolateFlip(Map<String, dynamic> params) {
  final Uint8List sourceBytes = params['bytes'] as Uint8List;
  final bool horizontal = params['horizontal'] as bool;
  final bool vertical = params['vertical'] as bool;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = _decodeNormalizedImage(sourceBytes);
  if (image == null) return null;

  img.Image flipped = image;
  if (horizontal) {
    flipped = img.flipHorizontal(flipped);
  }
  if (vertical) {
    flipped = img.flipVertical(flipped);
  }

  final bytes = Uint8List.fromList(
    _encodeImage(flipped, format: format, quality: quality),
  );

  return ResizeResult(
    bytes: bytes,
    width: flipped.width,
    height: flipped.height,
    fileSize: bytes.length,
  );
}


ResizeResult? _isolateResizeToPreset(Map<String, dynamic> params) {
  final Uint8List sourceBytes = params['bytes'] as Uint8List;
  final int targetWidth = params['targetWidth'] as int;
  final int targetHeight = params['targetHeight'] as int;
  final OutputImageFormat format = params['format'] as OutputImageFormat;
  final int quality = params['quality'] as int;

  final image = _decodeNormalizedImage(sourceBytes);
  if (image == null) return null;

  final sourceAspect = image.width / image.height;
  final targetAspect = targetWidth / targetHeight;

  img.Image resized;
  if (sourceAspect > targetAspect) {
    final scaledHeight = targetHeight;
    final scaledWidth = (scaledHeight * sourceAspect).round();
    resized = img.copyResize(
      image,
      width: scaledWidth,
      height: scaledHeight,
      interpolation: img.Interpolation.average,
    );
    final cropX = ((resized.width - targetWidth) / 2).round();
    resized = img.copyCrop(
      resized,
      x: cropX.clamp(0, math.max(0, resized.width - targetWidth)),
      y: 0,
      width: targetWidth,
      height: targetHeight,
    );
  } else {
    final scaledWidth = targetWidth;
    final scaledHeight = (scaledWidth * image.height / image.width).round();
    resized = img.copyResize(
      image,
      width: scaledWidth,
      height: scaledHeight,
      interpolation: img.Interpolation.average,
    );
    final cropY = ((resized.height - targetHeight) / 2).round();
    resized = img.copyCrop(
      resized,
      x: 0,
      y: cropY.clamp(0, math.max(0, resized.height - targetHeight)),
      width: targetWidth,
      height: targetHeight,
    );
  }

  final bytes = Uint8List.fromList(
    _encodeImage(resized, format: format, quality: quality),
  );

  return ResizeResult(
    bytes: bytes,
    width: resized.width,
    height: resized.height,
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
    OutputImageFormat.jpg => img.JpegEncoder(
      quality: clampedQuality,
    ).encode(image),
    OutputImageFormat.png => img.PngEncoder(
      level: ((100 - clampedQuality) / 11).round().clamp(0, 9),
    ).encode(image),
    OutputImageFormat.webp => img.PngEncoder(
      level: ((100 - clampedQuality) / 11).round().clamp(0, 9),
    ).encode(image),
  };
}

class ImageEditNotifier extends StateNotifier<ImageEditState> {
  ImageEditNotifier() : super(const ImageEditState());

  Future<void> loadImage(Uint8List bytes, String fileName) async {
    state = state.copyWith(isLoading: true, clearError: true);

    if (bytes.length > 50 * 1024 * 1024) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Image is too large (>50MB). Please choose a smaller image.',
      );
      return;
    }

    try {
      final dimensions = await Isolate.run<Map<String, int>?>(
        () => _isolateDecodeDimensions(bytes),
      );

      if (dimensions == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to decode image.',
        );
        return;
      }

      state = ImageEditState(
        originalBytes: bytes,
        currentBytes: bytes,
        fileName: fileName,
        width: dimensions['width']!,
        height: dimensions['height']!,
        fileSize: bytes.length,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<ResizeResult?> generateResize({
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await Isolate.run<ResizeResult?>(
        () => _isolateResize(<String, dynamic>{
          'bytes': sourceBytes,
          'width': width,
          'height': height,
          'format': format,
          'quality': quality,
        }),
      );
      return result;
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<int?> estimateResizeBytes({
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final preview = await generateResize(
      width: width,
      height: height,
      format: format,
      quality: quality,
    );
    return preview?.fileSize;
  }

  Future<ResizeResult?> compressToTargetSize(
    int targetBytes,
    OutputImageFormat format,
  ) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      state = state.copyWith(isLoading: true, clearError: true);

      final result = await ImageProcessorService.compressToTargetSize(
        bytes: sourceBytes,
        targetBytes: targetBytes,
        format: format,
      );

      if (result == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage:
              'Could not compress to target size.',
        );
        return null;
      }

      state = state.copyWith(isLoading: false, clearError: true);
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> generateCrop({
    required int x,
    required int y,
    required int width,
    required int height,
    OutputImageFormat format = OutputImageFormat.jpg,
    int quality = 95,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await Isolate.run<ResizeResult?>(
        () => _isolateCrop(<String, dynamic>{
          'bytes': sourceBytes,
          'x': x,
          'y': y,
          'width': width,
          'height': height,
          'format': format,
          'quality': quality,
        }),
      );
      return result;
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> generateRotate90() async {
    return generateRotate(
      angleDegrees: 90,
      format: OutputImageFormat.jpg,
      quality: 95,
    );
  }

  Future<ResizeResult?> generateRotate({
    required double angleDegrees,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await Isolate.run<ResizeResult?>(
        () => _isolateRotate(<String, dynamic>{
          'bytes': sourceBytes,
          'angle': angleDegrees,
          'format': format,
          'quality': quality,
        }),
      );
      return result;
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> generateRotateLeft90() async {
    return generateRotate(
      angleDegrees: -90,
      format: OutputImageFormat.jpg,
      quality: 95,
    );
  }

  Future<ResizeResult?> generateFlip(
    bool horizontal,
    bool vertical, {
    required OutputImageFormat format,
    required int quality,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await Isolate.run<ResizeResult?>(
        () => _isolateFlip(<String, dynamic>{
          'bytes': sourceBytes,
          'horizontal': horizontal,
          'vertical': vertical,
          'format': format,
          'quality': quality,
        }),
      );
      return result;
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> resizeToPreset(
    int targetWidth,
    int targetHeight,
    OutputImageFormat format,
    int quality,
  ) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await Isolate.run<ResizeResult?>(
        () => _isolateResizeToPreset(<String, dynamic>{
          'bytes': sourceBytes,
          'targetWidth': targetWidth,
          'targetHeight': targetHeight,
          'format': format,
          'quality': quality,
        }),
      );
      return result;
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  void replaceWithResult({
    required ResizeResult result,
    required String fileName,
  }) {
    state = state.copyWith(
      currentBytes: result.bytes,
      fileName: fileName,
      width: result.width,
      height: result.height,
      fileSize: result.fileSize,
      isLoading: false,
      clearError: true,
    );
  }

  void setLoading(bool value) {
    state = state.copyWith(isLoading: value, clearError: value);
  }

  void clear() {
    state = const ImageEditState();
  }

  Future<void> restoreImageBytes(Uint8List bytes) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final dimensions = await Isolate.run<Map<String, int>?>(
        () => _isolateDecodeDimensions(bytes),
      );

      if (dimensions == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to decode image bytes.',
        );
        return;
      }

      state = state.copyWith(
        currentBytes: bytes,
        width: dimensions['width']!,
        height: dimensions['height']!,
        fileSize: bytes.length,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<ResizeResult?> generateWatermark({
    required String text,
    required Color color,
    required WatermarkTextSize textSize,
    required double opacity,
    required WatermarkPosition position,
    OutputImageFormat format = OutputImageFormat.jpg,
    int quality = 95,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null || text.trim().isEmpty) return null;

    try {
      ui.Codec codec;
      try {
        codec = await ui.instantiateImageCodec(sourceBytes);
      } catch (_) {
        final decoded = img.decodeImage(sourceBytes);
        if (decoded == null) return null;
        final pngBytes = Uint8List.fromList(img.encodePng(decoded));
        codec = await ui.instantiateImageCodec(pngBytes);
      }

      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final imgWidth = uiImage.width;
      final imgHeight = uiImage.height;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      canvas.drawImage(uiImage, ui.Offset.zero, Paint());

      final minDim = math.min(imgWidth, imgHeight);
      final calculatedFontSize = math.max(12.0, minDim * textSize.scaleFactor);

      final finalColor = color.withValues(alpha: opacity.clamp(0.1, 1.0));

      final textStyle = TextStyle(
        color: finalColor,
        fontSize: calculatedFontSize,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 4.0,
            color: Colors.black.withValues(
              alpha: (opacity * 0.6).clamp(0.0, 1.0),
            ),
            offset: const Offset(1.5, 1.5),
          ),
        ],
      );

      final textSpan = TextSpan(text: text, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final textWidth = textPainter.width;
      final textHeight = textPainter.height;

      final margin = math.max(12.0, minDim * 0.03);

      double dx;
      double dy;

      switch (position) {
        case WatermarkPosition.topLeft:
          dx = margin;
          dy = margin;
          break;
        case WatermarkPosition.topRight:
          dx = imgWidth - textWidth - margin;
          dy = margin;
          break;
        case WatermarkPosition.bottomLeft:
          dx = margin;
          dy = imgHeight - textHeight - margin;
          break;
        case WatermarkPosition.bottomRight:
          dx = imgWidth - textWidth - margin;
          dy = imgHeight - textHeight - margin;
          break;
        case WatermarkPosition.center:
          dx = (imgWidth - textWidth) / 2;
          dy = (imgHeight - textHeight) / 2;
          break;
      }

      dx = dx.clamp(0.0, math.max(0.0, imgWidth - textWidth));
      dy = dy.clamp(0.0, math.max(0.0, imgHeight - textHeight));

      textPainter.paint(canvas, ui.Offset(dx, dy));

      final picture = recorder.endRecording();
      final imgRendered = await picture.toImage(imgWidth, imgHeight);
      final byteData = await imgRendered.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) return null;
      var resultBytes = byteData.buffer.asUint8List();

      if (format != OutputImageFormat.png || quality < 100) {
        final decoded = img.decodeImage(resultBytes);
        if (decoded != null) {
          final encoded = _encodeImage(decoded, format: format, quality: quality);
          resultBytes = Uint8List.fromList(encoded);
        }
      }

      return ResizeResult(
        bytes: resultBytes,
        width: imgWidth,
        height: imgHeight,
        fileSize: resultBytes.length,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  void resetToOriginal() {
    final originalBytes = state.originalBytes;
    if (originalBytes == null) return;

    final image = img.decodeImage(originalBytes);
    if (image == null) return;

    state = ImageEditState(
      originalBytes: originalBytes,
      currentBytes: originalBytes,
      fileName: state.fileName,
      width: image.width,
      height: image.height,
      fileSize: originalBytes.length,
    );
  }
}

final imageEditProvider =
    StateNotifierProvider<ImageEditNotifier, ImageEditState>((ref) {
      return ImageEditNotifier();
    });
