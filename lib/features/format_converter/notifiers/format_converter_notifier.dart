import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/settings/app_settings.dart';
import '../../../shared/models/picked_file.dart';
import '../../../shared/services/watermark_helper.dart';

enum ConvertFormat {
  jpg('JPG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png'),
  webp('WEBP', 'webp', 'image/webp'),
  pdf('PDF', 'pdf', 'application/pdf'),
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
    this.files = const <PickedFile>[],
    this.images = const <ConvertibleImage>[],
    this.selectedFormat = ConvertFormat.jpg,
    this.quality = 90,
    this.isConverting = false,
    this.progress = 0,
    this.totalConverted = 0,
    this.currentConvertingIndex = 0,
    this.totalToConvert = 0,
    this.convertingStatusText,
    this.errorMessage,
  });

  final List<PickedFile> files;
  final List<ConvertibleImage> images;
  final ConvertFormat selectedFormat;
  final int quality;
  final bool isConverting;
  final double progress;
  final int totalConverted;
  final int currentConvertingIndex;
  final int totalToConvert;
  final String? convertingStatusText;
  final String? errorMessage;

  int get totalImages => images.length;
  int get pendingCount => images.where((i) => i.status == ConvertStatus.pending).length;
  int get successCount => images.where((i) => i.status == ConvertStatus.success).length;
  int get failedCount => images.where((i) => i.status == ConvertStatus.failed).length;
  int get totalOriginalSize => images.fold(0, (sum, i) => sum + i.sizeBytes);
  int get totalConvertedSize => images.fold(0, (sum, i) => sum + i.convertedSizeBytes);

  FormatConverterState copyWith({
    List<PickedFile>? files,
    List<ConvertibleImage>? images,
    ConvertFormat? selectedFormat,
    int? quality,
    bool? isConverting,
    double? progress,
    int? totalConverted,
    int? currentConvertingIndex,
    int? totalToConvert,
    String? convertingStatusText,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FormatConverterState(
      files: files ?? this.files,
      images: images ?? this.images,
      selectedFormat: selectedFormat ?? this.selectedFormat,
      quality: quality ?? this.quality,
      isConverting: isConverting ?? this.isConverting,
      progress: progress ?? this.progress,
      totalConverted: totalConverted ?? this.totalConverted,
      currentConvertingIndex: currentConvertingIndex ?? this.currentConvertingIndex,
      totalToConvert: totalToConvert ?? this.totalToConvert,
      convertingStatusText: convertingStatusText ?? this.convertingStatusText,
      errorMessage: clearError ? null : errorMessage,
    );
  }
}

final formatConverterProvider =
    StateNotifierProvider<FormatConverterNotifier, FormatConverterState>(
  (ref) => FormatConverterNotifier(ref),
);

class FormatConverterNotifier extends StateNotifier<FormatConverterState> {
  FormatConverterNotifier([this._ref]) : super(const FormatConverterState());

  final Ref? _ref;

  void setFormat(ConvertFormat format) {
    state = state.copyWith(selectedFormat: format, clearError: true);
  }

  void setQuality(int quality) {
    state = state.copyWith(quality: quality);
  }

  void addPickedFiles(List<PickedFile> pickedFiles) {
    final updatedFiles = [...state.files, ...pickedFiles];
    state = state.copyWith(files: updatedFiles);

    final imageFiles = pickedFiles
        .where((f) => f.bytes != null)
        .map((f) => <String, dynamic>{
              'name': f.name,
              'path': f.path ?? '',
              'sizeBytes': f.sizeBytes,
              'bytes': f.bytes,
            })
        .toList();

    if (imageFiles.isNotEmpty) {
      addImages(imageFiles);
    }
  }

  Future<void> addImages(List<Map<String, dynamic>> imageFiles) async {
    final newImages = <ConvertibleImage>[];

    for (final file in imageFiles) {
      final path = file['path'] as String;
      final name = file['name'] as String;
      final sizeBytes = file['sizeBytes'] as int;
      final bytes = file['bytes'] as Uint8List?;

      final ext = name.contains('.')
          ? name.split('.').last.toLowerCase()
          : '';
      final format = _detectFormatFromExtension(ext);

      if (format == null) continue;

      int? width;
      int? height;
      if (bytes != null) {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            width = decoded.width;
            height = decoded.height;
          }
        } catch (_) {}
      }

      newImages.add(
        ConvertibleImage(
          name: name,
          path: path,
          sizeBytes: sizeBytes,
          originalFormat: format,
          bytes: bytes,
          width: width ?? 0,
          height: height ?? 0,
        ),
      );
    }

    if (newImages.isEmpty) return;

    final updated = [...state.images, ...newImages];
    state = state.copyWith(images: updated, clearError: true);

    final needLoading = newImages.where((i) => i.bytes == null).toList();
    if (needLoading.isNotEmpty) {
      await _loadImages(needLoading);
    }
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
    }
    state = state.copyWith(images: updated);

    await Future.wait(
      imagesToLoad.map((imageToLoad) async {
        final index = updated.indexWhere((u) => u.path == imageToLoad.path);
        if (index == -1) return;

        try {
          final file = File(imageToLoad.path);
          final bytes = await file.readAsBytes();

          final decoded = img.decodeImage(bytes);
          if (decoded == null) {
            updated[index] = updated[index].copyWith(
              status: ConvertStatus.failed,
              error: 'Invalid or corrupted image',
            );
          } else {
            updated[index] = updated[index].copyWith(
              bytes: bytes,
              width: decoded.width,
              height: decoded.height,
              status: ConvertStatus.pending,
            );
          }
        } catch (e) {
          updated[index] = updated[index].copyWith(
            status: ConvertStatus.failed,
            error: 'Failed to load: ${e.toString()}',
          );
        }
      }),
    );

    state = state.copyWith(images: updated);
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

    final total = pendingImages.length;

    state = state.copyWith(
      isConverting: true,
      progress: 0,
      totalConverted: 0,
      currentConvertingIndex: 1,
      totalToConvert: total,
      convertingStatusText: 'Converting file 1 of $total...',
      clearError: true,
    );

    final updated = <ConvertibleImage>[...state.images];
    int converted = 0;

    for (int i = 0; i < updated.length; i++) {
      final image = updated[i];
      if (image.status != ConvertStatus.pending || image.bytes == null) continue;

      final currentIndex = converted + 1;
      final statusMsg = 'Converting file $currentIndex of $total...';

      updated[i] = image.copyWith(status: ConvertStatus.converting);
      state = state.copyWith(
        images: updated,
        currentConvertingIndex: currentIndex,
        totalToConvert: total,
        convertingStatusText: statusMsg,
        progress: (converted / total) * 100,
      );

      try {
        var decoded = img.decodeImage(image.bytes!);
        if (decoded == null) {
          updated[i] = image.copyWith(
            status: ConvertStatus.failed,
            error: 'Failed to decode',
          );
          continue;
        }

        final settings = _ref?.read(appSettingsProvider);
        if (settings != null && settings.enableGlobalWatermark) {
          decoded = WatermarkHelper.applyToImage(decoded, settings);
        }

        Uint8List convertedBytes;

        if (state.selectedFormat == ConvertFormat.jpg ||
            state.selectedFormat == ConvertFormat.bmp) {
          final flattened = _flattenAlpha(decoded);
          convertedBytes = await _encodeImageAsync(flattened, image.bytes!, state.selectedFormat);
        } else {
          convertedBytes = await _encodeImageAsync(decoded, image.bytes!, state.selectedFormat);
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
        progress: (converted / total) * 100,
        totalConverted: converted,
        convertingStatusText: converted == total
            ? 'Completed'
            : 'Converting file ${converted + 1} of $total...',
      );
    }

    state = state.copyWith(
      isConverting: false,
      progress: 100,
      convertingStatusText: 'Converted $converted of $total files',
    );
  }

  Future<Uint8List> _encodeImageAsync(
    img.Image image,
    Uint8List originalBytes,
    ConvertFormat format, {
    bool stripExif = true,
  }) async {
    if (stripExif) {
      image.exif.clear();
    }
    switch (format) {
      case ConvertFormat.jpg:
        return img.encodeJpg(image, quality: state.quality.clamp(1, 100));
      case ConvertFormat.png:
        return img.encodePng(image);
      case ConvertFormat.webp:
        return img.encodePng(image);
      case ConvertFormat.pdf:
        return _convertToPdf(originalBytes, image);
      case ConvertFormat.bmp:
        return img.encodeBmp(image);
      case ConvertFormat.tiff:
        return img.encodeTiff(image);
    }
  }

  Future<Uint8List> _convertToPdf(Uint8List imageBytes, img.Image decoded) async {
    final pdf = pw.Document();
    final pdfImage = pw.MemoryImage(imageBytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          decoded.width.toDouble(),
          decoded.height.toDouble(),
        ),
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
          );
        },
      ),
    );
    return await pdf.save();
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
