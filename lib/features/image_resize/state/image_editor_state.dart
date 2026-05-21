import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_presets.dart';
import '../services/image_processor_service.dart';

class ImageEditorState {
  const ImageEditorState({
    this.originalBytes,
    this.currentBytes,
    this.fileName,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    this.isLoading = false,
    this.progress = 0,
    this.errorMessage,
    this.warningMessage,
  });

  final Uint8List? originalBytes;
  final Uint8List? currentBytes;
  final String? fileName;
  final int width;
  final int height;
  final int fileSize;
  final bool isLoading;
  final double progress;
  final String? errorMessage;
  final String? warningMessage;

  bool get hasImage => currentBytes != null;

  ImageEditorState copyWith({
    Uint8List? originalBytes,
    Uint8List? currentBytes,
    String? fileName,
    int? width,
    int? height,
    int? fileSize,
    bool? isLoading,
    double? progress,
    String? errorMessage,
    String? warningMessage,
    bool clearError = false,
    bool clearWarning = false,
  }) {
    return ImageEditorState(
      originalBytes: originalBytes ?? this.originalBytes,
      currentBytes: currentBytes ?? this.currentBytes,
      fileName: fileName ?? this.fileName,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : errorMessage,
      warningMessage: clearWarning ? null : warningMessage,
    );
  }
}

class ImageEditorNotifier extends AsyncNotifier<ImageEditorState> {
  @override
  Future<ImageEditorState> build() async {
    return const ImageEditorState();
  }

  Future<void> loadImage(Uint8List bytes, String fileName) async {
    state = const AsyncValue.loading();
    try {
      if (bytes.length > 50 * 1024 * 1024) {
        state = AsyncValue.data(
          const ImageEditorState(
            errorMessage: 'Image is too large (>50MB). Please choose a smaller image.',
          ),
        );
        return;
      }

      final info = await ImageProcessorService.decodeImageInfo(bytes);
      if (info == null) {
        state = AsyncValue.data(
          const ImageEditorState(
            errorMessage: 'Failed to decode image.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        ImageEditorState(
          originalBytes: bytes,
          currentBytes: bytes,
          fileName: fileName,
          width: info.width,
          height: info.height,
          fileSize: bytes.length,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        ImageEditorState(
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> resize({
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true),
    );

    try {
      final result = await ImageProcessorService.resize(
        bytes: currentState.currentBytes!,
        width: width,
        height: height,
        format: format,
        quality: quality,
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Resize failed.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> crop({
    required int x,
    required int y,
    required int width,
    required int height,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true),
    );

    try {
      final result = await ImageProcessorService.crop(
        bytes: currentState.currentBytes!,
        x: x,
        y: y,
        width: width,
        height: height,
        format: format,
        quality: quality,
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Crop failed.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> rotate({
    required double angle,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true),
    );

    try {
      final result = await ImageProcessorService.rotate(
        bytes: currentState.currentBytes!,
        angle: angle,
        format: format,
        quality: quality,
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Rotation failed.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> flip({
    required bool horizontal,
    required bool vertical,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true),
    );

    try {
      final result = await ImageProcessorService.flip(
        bytes: currentState.currentBytes!,
        horizontal: horizontal,
        vertical: vertical,
        format: format,
        quality: quality,
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Flip failed.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> compressToTargetSize({
    required int targetBytes,
    required OutputImageFormat format,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true, clearWarning: true),
    );

    try {
      final result = await ImageProcessorService.compressToTargetSize(
        bytes: currentState.currentBytes!,
        targetBytes: targetBytes,
        format: format,
        onProgress: (progress) {
          final current = state.value;
          if (current != null) {
            state = AsyncValue.data(
              current.copyWith(progress: progress),
            );
          }
        },
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Could not compress to target size. Minimum quality reached.',
          ),
        );
        return;
      }

      if (result.fileSize > targetBytes) {
        state = AsyncValue.data(
          currentState.copyWith(
            currentBytes: result.bytes,
            width: result.width,
            height: result.height,
            fileSize: result.fileSize,
            isLoading: false,
            progress: 1,
            clearError: true,
            warningMessage: 'Minimum quality reached. Final size: ${(result.fileSize / 1024).round()} KB.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> resizeToPreset({
    required SocialPreset preset,
    required OutputImageFormat format,
    required int quality,
  }) async {
    final currentState = state.value;
    if (currentState == null || !currentState.hasImage) return;

    state = AsyncValue.data(
      currentState.copyWith(isLoading: true, progress: 0, clearError: true),
    );

    try {
      final result = await ImageProcessorService.resizeToPreset(
        bytes: currentState.currentBytes!,
        preset: preset,
        format: format,
        quality: quality,
      );

      if (result == null) {
        state = AsyncValue.data(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'Preset resize failed.',
          ),
        );
        return;
      }

      state = AsyncValue.data(
        currentState.copyWith(
          currentBytes: result.bytes,
          width: result.width,
          height: result.height,
          fileSize: result.fileSize,
          isLoading: false,
          progress: 1,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue.data(
        currentState.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void resetToOriginal() {
    final currentState = state.value;
    final originalBytes = currentState?.originalBytes;
    if (originalBytes == null) return;

    final image = ImageProcessorService.decodeImageInfo(originalBytes);
    image.then((info) {
      if (info != null) {
        state = AsyncValue.data(
          currentState!.copyWith(
            currentBytes: originalBytes,
            width: info.width,
            height: info.height,
            fileSize: originalBytes.length,
            clearError: true,
            clearWarning: true,
          ),
        );
      }
    });
  }

  void clear() {
    state = const AsyncValue.data(ImageEditorState());
  }
}

final imageEditorProvider =
    AsyncNotifierProvider<ImageEditorNotifier, ImageEditorState>(
  ImageEditorNotifier.new,
);
