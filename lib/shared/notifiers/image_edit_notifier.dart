import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

enum ResizeOutputFormat {
  jpg('JPG', 'jpg'),
  png('PNG', 'png');

  const ResizeOutputFormat(this.label, this.extension);

  final String label;
  final String extension;
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

class ImageEditNotifier extends StateNotifier<ImageEditState> {
  ImageEditNotifier() : super(const ImageEditState());

  Future<void> loadImage(Uint8List bytes, String fileName) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final image = img.decodeImage(bytes);
      if (image == null) {
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
        width: image.width,
        height: image.height,
        fileSize: bytes.length,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<ResizeResult?> generateResize({
    required int width,
    required int height,
    required ResizeOutputFormat format,
    required int quality,
  }) async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final image = img.decodeImage(sourceBytes);
      if (image == null) {
        state = state.copyWith(errorMessage: 'Failed to process image.');
        return null;
      }

      final safeWidth = width.clamp(1, 12000);
      final safeHeight = height.clamp(1, 12000);
      final resized = img.copyResize(
        image,
        width: safeWidth,
        height: safeHeight,
        interpolation: img.Interpolation.average,
      );
      final bytes = Uint8List.fromList(
        _encodeImage(resized, format: format, quality: quality),
      );

      return ResizeResult(
        bytes: bytes,
        width: resized.width,
        height: resized.height,
        fileSize: bytes.length,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString());
      return null;
    }
  }

  Future<int?> estimateResizeBytes({
    required int width,
    required int height,
    required ResizeOutputFormat format,
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

   Future<ResizeResult?> generateCrop({
     required int x,
     required int y,
     required int width,
     required int height,
   }) async {
     final sourceBytes = state.currentBytes;
     if (sourceBytes == null) return null;

     try {
       final image = img.decodeImage(sourceBytes);
       if (image == null) {
         state = state.copyWith(errorMessage: 'Failed to process image.');
         return null;
       }

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
       final bytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 95));

       return ResizeResult(
         bytes: bytes,
         width: cropped.width,
         height: cropped.height,
         fileSize: bytes.length,
       );
     } catch (error) {
       state = state.copyWith(errorMessage: error.toString());
       return null;
     }
   }

  Future<ResizeResult?> generateRotate90() async {
    final sourceBytes = state.currentBytes;
    if (sourceBytes == null) return null;

    try {
      final image = img.decodeImage(sourceBytes);
      if (image == null) {
        state = state.copyWith(errorMessage: 'Failed to process image.');
        return null;
      }

      final rotated = img.copyRotate(image, angle: 90);

      final bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));

      return ResizeResult(
        bytes: bytes,
        width: rotated.width,
        height: rotated.height,
        fileSize: bytes.length,
      );
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

  List<int> _encodeImage(
    img.Image image, {
    required ResizeOutputFormat format,
    required int quality,
  }) {
    final clampedQuality = quality.clamp(1, 100);
    return switch (format) {
      ResizeOutputFormat.jpg => img.encodeJpg(image, quality: clampedQuality),
      ResizeOutputFormat.png => img.encodePng(
        image,
        level: ((100 - clampedQuality) / 11).round().clamp(0, 9),
      ),
    };
  }
}

final imageEditProvider =
    StateNotifierProvider<ImageEditNotifier, ImageEditState>((ref) {
      return ImageEditNotifier();
    });
