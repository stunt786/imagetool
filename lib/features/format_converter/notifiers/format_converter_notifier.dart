import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

enum ConvertFormat {
  jpg('JPG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png'),
  bmp('BMP', 'bmp', 'image/bmp'),
  tiff('TIFF', 'tiff', 'image/tiff');

  const ConvertFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

@immutable
class ConvertibleImage {
  const ConvertibleImage({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.originalFormat,
    this.width = 0,
    this.height = 0,
    this.bytes,
    this.convertedBytes,
    this.convertedSizeBytes = 0,
    this.status = ConvertStatus.pending,
    this.error,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final String originalFormat;
  final int width;
  final int height;
  final Uint8List? bytes;
  final Uint8List? convertedBytes;
  final int convertedSizeBytes;
  final ConvertStatus status;
  final String? error;

  String get baseName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  ConvertibleImage copyWith({
    Uint8List? bytes,
    Uint8List? convertedBytes,
    int? convertedSizeBytes,
    ConvertStatus? status,
    String? error,
    int? width,
    int? height,
  }) {
    return ConvertibleImage(
      name: name,
      path: path,
      sizeBytes: sizeBytes,
      originalFormat: originalFormat,
      width: width ?? this.width,
      height: height ?? this.height,
      bytes: bytes ?? this.bytes,
      convertedBytes: convertedBytes ?? this.convertedBytes,
      convertedSizeBytes: convertedSizeBytes ?? this.convertedSizeBytes,
      status: status ?? this.status,
      error: error,
    );
  }
}

enum ConvertStatus { pending, loading, converting, success, failed, removed }

@immutable
class FormatConverterState {
  const FormatConverterState({
    this.images = const <ConvertibleImage>[],
    this.selectedFormat = ConvertFormat.jpg,
    this.quality = 90,
    this.isConverting = false,
    this.progress = 0,
    this.totalConverted = 0,
    this.errorMessage,
  });

  final List<ConvertibleImage> images;
  final ConvertFormat selectedFormat;
  final int quality;
  final bool isConverting;
  final double progress;
  final int totalConverted;
  final String? errorMessage;

  int get totalImages => images.length;
  int get pendingCount => images.where((i) => i.status == ConvertStatus.pending).length;
  int get successCount => images.where((i) => i.status == ConvertStatus.success).length;
  int get failedCount => images.where((i) => i.status == ConvertStatus.failed).length;
  int get totalOriginalSize => images.fold(0, (sum, i) => sum + i.sizeBytes);
  int get totalConvertedSize => images.fold(0, (sum, i) => sum + i.convertedSizeBytes);

  FormatConverterState copyWith({
    List<ConvertibleImage>? images,
    ConvertFormat? selectedFormat,
    int? quality,
    bool? isConverting,
    double? progress,
    int? totalConverted,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FormatConverterState(
      images: images ?? this.images,
      selectedFormat: selectedFormat ?? this.selectedFormat,
      quality: quality ?? this.quality,
      isConverting: isConverting ?? this.isConverting,
      progress: progress ?? this.progress,
      totalConverted: totalConverted ?? this.totalConverted,
      errorMessage: clearError ? null : errorMessage,
    );
  }
}

final formatConverterProvider =
    StateNotifierProvider<FormatConverterNotifier, FormatConverterState>(
  (ref) => FormatConverterNotifier(),
);

class FormatConverterNotifier extends StateNotifier<FormatConverterState> {
  FormatConverterNotifier() : super(const FormatConverterState());

  void setFormat(ConvertFormat format) {
    state = state.copyWith(selectedFormat: format, clearError: true);
  }

  void setQuality(int quality) {
    state = state.copyWith(quality: quality);
  }

  Future<void> addImages(List<Map<String, dynamic>> imageFiles) async {
    final newImages = <ConvertibleImage>[];

    for (final file in imageFiles) {
      final path = file['path'] as String;
      final name = file['name'] as String;
      final sizeBytes = file['sizeBytes'] as int;

      final ext = name.contains('.')
          ? name.split('.').last.toLowerCase()
          : '';
      final format = _detectFormatFromExtension(ext);

      if (format == null) continue;

      newImages.add(
        ConvertibleImage(
          name: name,
          path: path,
          sizeBytes: sizeBytes,
          originalFormat: format,
        ),
      );
    }

    if (newImages.isEmpty) return;

    final updated = [...state.images, ...newImages];
    state = state.copyWith(images: updated, clearError: true);

    await _loadImages(newImages);
  }

  Future<void> _loadImages(List<ConvertibleImage> imagesToLoad) async {
    final updated = <ConvertibleImage>[...state.images];

    for (int i = 0; i < updated.length; i++) {
      final image = updated[i];
      if (image.status != ConvertStatus.pending) continue;

      final newImageIndex = imagesToLoad.indexWhere(
        (n) => n.path == image.path,
      );
      if (newImageIndex == -1) continue;

      updated[i] = image.copyWith(status: ConvertStatus.loading);
      state = state.copyWith(images: updated);

      try {
        final file = File(image.path);
        final bytes = await file.readAsBytes();

        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          updated[i] = updated[i].copyWith(
            status: ConvertStatus.failed,
            error: 'Invalid or corrupted image',
          );
        } else {
          updated[i] = updated[i].copyWith(
            bytes: bytes,
            width: decoded.width,
            height: decoded.height,
            status: ConvertStatus.pending,
          );
        }
      } catch (e) {
        updated[i] = updated[i].copyWith(
          status: ConvertStatus.failed,
          error: 'Failed to load: ${e.toString()}',
        );
      }

      state = state.copyWith(images: updated);
    }
  }

  Future<void> convertAll() async {
    final pendingImages = state.images
        .where((i) => i.status == ConvertStatus.pending && i.bytes != null)
        .toList();

    if (pendingImages.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No valid images to convert',
      );
      return;
    }

    state = state.copyWith(
      isConverting: true,
      progress: 0,
      totalConverted: 0,
      clearError: true,
    );

    final updated = <ConvertibleImage>[...state.images];
    int converted = 0;

    for (int i = 0; i < updated.length; i++) {
      final image = updated[i];
      if (image.status != ConvertStatus.pending || image.bytes == null) continue;

      updated[i] = image.copyWith(status: ConvertStatus.converting);
      state = state.copyWith(images: updated);

      try {
        final decoded = img.decodeImage(image.bytes!);
        if (decoded == null) {
          updated[i] = image.copyWith(
            status: ConvertStatus.failed,
            error: 'Failed to decode',
          );
          continue;
        }

        Uint8List convertedBytes;

        if (state.selectedFormat == ConvertFormat.jpg ||
            state.selectedFormat == ConvertFormat.bmp) {
          final flattened = _flattenAlpha(decoded);
          convertedBytes = _encodeImage(flattened, state.selectedFormat);
        } else {
          convertedBytes = _encodeImage(decoded, state.selectedFormat);
        }

        updated[i] = image.copyWith(
          convertedBytes: convertedBytes,
          convertedSizeBytes: convertedBytes.length,
          status: ConvertStatus.success,
        );
        converted++;
      } catch (e) {
        updated[i] = image.copyWith(
          status: ConvertStatus.failed,
          error: e.toString(),
        );
      }

      state = state.copyWith(
        images: updated,
        progress: (converted / pendingImages.length) * 100,
        totalConverted: converted,
      );
    }

    state = state.copyWith(
      isConverting: false,
      progress: 100,
    );
  }

  Uint8List _encodeImage(img.Image image, ConvertFormat format) {
    return switch (format) {
      ConvertFormat.jpg =>
        img.encodeJpg(image, quality: state.quality.clamp(1, 100)),
      ConvertFormat.png => img.encodePng(image),
      ConvertFormat.bmp => img.encodeBmp(image),
      ConvertFormat.tiff => img.encodeTiff(image),
    };
  }

  img.Image _flattenAlpha(img.Image image) {
    if (!image.hasAlpha) return image;

    final flattened = img.Image(
      width: image.width,
      height: image.height,
    );

    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, image);

    return flattened;
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final updated = [...state.images];
    updated[index] = updated[index].copyWith(status: ConvertStatus.removed);
    state = state.copyWith(
      images: updated.where((i) => i.status != ConvertStatus.removed).toList(),
    );
  }

  void clearAll() {
    state = const FormatConverterState();
  }

  void resetFailed() {
    final updated = state.images.map((image) {
      if (image.status == ConvertStatus.failed) {
        return image.copyWith(
          status: ConvertStatus.pending,
          error: null,
          convertedBytes: null,
          convertedSizeBytes: 0,
        );
      }
      return image;
    }).toList();
    state = state.copyWith(images: updated, clearError: true);
  }
}

String? _detectFormatFromExtension(String ext) {
  final validFormats = {
    'jpg': 'JPEG',
    'jpeg': 'JPEG',
    'png': 'PNG',
    'webp': 'WebP',
    'gif': 'GIF',
    'bmp': 'BMP',
    'tif': 'TIFF',
    'tiff': 'TIFF',
    'heic': 'HEIC',
    'heif': 'HEIF',
    'avif': 'AVIF',
  };
  return validFormats[ext];
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
