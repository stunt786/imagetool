import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/settings/app_settings.dart';
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
    this.sourcePath,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  final Uint8List? originalBytes;
  final Uint8List? currentBytes;
  final String? fileName;
  final String? sourcePath;
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
    String? sourcePath,
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
      sourcePath: sourcePath ?? this.sourcePath,
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
        level: ((100 - clampedQuality) / 16).round().clamp(0, 6),
      ).encode(image),
    OutputImageFormat.webp => img.encodeWebP(
        image,
        lossless: clampedQuality >= 100,
        quality: clampedQuality,
      ),
  };
}

class ImageEditNotifier extends StateNotifier<ImageEditState> {
  ImageEditNotifier() : super(const ImageEditState());

  Future<void> loadImage(
    Uint8List bytes,
    String fileName, {
    String? sourcePath,
  }) async {
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
        sourcePath: sourcePath,
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
    AppSettingsState? settings,
    bool preserveAspectRatio = true,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.resize(
        bytes: sourceBytes,
        width: width,
        height: height,
        format: format,
        quality: quality,
        settings: settings,
        preserveAspectRatio: preserveAspectRatio,
        onProgress: onProgress,
      );
      if (result == null) return null;
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
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
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;
    try {
      return await ImageProcessorService.estimateResizeBytes(
        bytes: sourceBytes,
        width: width,
        height: height,
        format: format,
        quality: quality,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<int?> estimatePresetBytes({
    required int targetWidth,
    required int targetHeight,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;
    try {
      return await ImageProcessorService.estimatePresetBytes(
        bytes: sourceBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        format: format,
        quality: quality,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> compressToTargetSize(
    int targetBytes,
    OutputImageFormat format, {
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.compressToTargetSize(
        bytes: sourceBytes,
        targetBytes: targetBytes,
        format: format,
        settings: settings,
        onProgress: onProgress,
      );

      if (result == null) {
        state = state.copyWith(
          errorMessage: 'Could not compress to target size.',
        );
        return null;
      }

      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
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
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.crop(
        bytes: sourceBytes,
        x: x,
        y: y,
        width: width,
        height: height,
        format: format,
        quality: quality,
        settings: settings,
        onProgress: onProgress,
      );
      if (result == null) return null;
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> generateRotate90({
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    return generateRotate(
      angleDegrees: 90,
      format: OutputImageFormat.jpg,
      quality: 95,
      settings: settings,
      onProgress: onProgress,
    );
  }

  Future<ResizeResult?> generateRotate({
    required double angleDegrees,
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.rotate(
        bytes: sourceBytes,
        angle: angleDegrees,
        format: format,
        quality: quality,
        settings: settings,
        onProgress: onProgress,
      );
      if (result == null) return null;
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> generateRotateLeft90({
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    return generateRotate(
      angleDegrees: -90,
      format: OutputImageFormat.jpg,
      quality: 95,
      settings: settings,
      onProgress: onProgress,
    );
  }

  Future<ResizeResult?> generateFlip(
    bool horizontal,
    bool vertical, {
    required OutputImageFormat format,
    required int quality,
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.flip(
        bytes: sourceBytes,
        horizontal: horizontal,
        vertical: vertical,
        format: format,
        quality: quality,
        settings: settings,
        onProgress: onProgress,
      );
      if (result == null) return null;
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<ResizeResult?> resizeToPreset(
    int targetWidth,
    int targetHeight,
    OutputImageFormat format,
    int quality, {
    AppSettingsState? settings,
    void Function(double progress)? onProgress,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final result = await ImageProcessorService.resizeToPreset(
        bytes: sourceBytes,
        preset: SocialPreset(
          name: '',
          width: targetWidth,
          height: targetHeight,
        ),
        format: format,
        quality: quality,
        settings: settings,
        onProgress: onProgress,
      );
      if (result == null) return null;
      return ResizeResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
        fileSize: result.fileSize,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  void replaceWithResult({
    required ResizeResult result,
    required String fileName,
    String? sourcePath,
  }) {
    state = state.copyWith(
      currentBytes: result.bytes,
      fileName: fileName,
      width: result.width,
      height: result.height,
      fileSize: result.fileSize,
      isLoading: false,
      clearError: true,
      sourcePath: sourcePath,
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
          final encoded =
              _encodeImage(decoded, format: format, quality: quality);
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
      sourcePath: state.sourcePath,
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
