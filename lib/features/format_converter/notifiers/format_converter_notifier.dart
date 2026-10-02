import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/image_isolate_service.dart';
import '../../../core/services/platform_image_encoder.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/utils/file_type_detector.dart';
import '../../../shared/models/picked_file.dart';
import '../../../shared/services/watermark_helper.dart';

/// Output formats offered by the converter.
///
/// `JPG` and `JPEG` are the same codec but are exposed separately so the user
/// can pick the filename extension they want.
enum ConvertFormat {
  jpg('JPG', 'jpg', 'image/jpeg'),
  jpeg('JPEG', 'jpeg', 'image/jpeg'),
  png('PNG', 'png', 'image/png'),
  webp('WEBP', 'webp', 'image/webp'),
  pdf('PDF', 'pdf', 'application/pdf'),
  bmp('BMP', 'bmp', 'image/bmp'),
  tiff('TIFF', 'tiff', 'image/tiff');

  const ConvertFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;

  bool get isJpeg => this == jpg || this == jpeg;

  bool get isPdf => this == pdf;

  /// Encoding target understood by the isolate workers.
  String get codec => isJpeg ? 'jpg' : extension;
}

enum ConvertStatus {
  /// Added by the user, waiting to be loaded.
  pending,

  /// Reading bytes / building a preview.
  loading,

  /// Loaded and ready to convert.
  ready,

  converting,
  success,

  /// Already in the requested format, nothing written.
  skipped,

  failed,
  removed,
}

@immutable
class ConvertibleImage {
  const ConvertibleImage({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.originalFormat,
    this.width = 0,
    this.height = 0,
    this.bytes,
    this.previewBytes,
    this.convertedBytes,
    this.convertedSizeBytes = 0,
    this.status = ConvertStatus.pending,
    this.error,
    this.note,
  });

  /// Stable identity used for async updates (paths alone can repeat).
  final String id;
  final String name;
  final String path;
  final int sizeBytes;

  /// Canonical source format detected from the file header.
  final String originalFormat;

  final int width;
  final int height;

  /// In-memory source bytes. Only populated when the picker handed us bytes
  /// and no readable path exists; otherwise the file is read on demand so a
  /// long batch does not hold every full-resolution image in memory.
  final Uint8List? bytes;

  /// Small preview used by list/grid widgets.
  final Uint8List? previewBytes;

  final Uint8List? convertedBytes;
  final int convertedSizeBytes;
  final ConvertStatus status;
  final String? error;
  final String? note;

  bool get isReadyToConvert =>
      status == ConvertStatus.pending || status == ConvertStatus.ready;

  String get baseName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  ConvertibleImage copyWith({
    Uint8List? bytes,
    Uint8List? previewBytes,
    Uint8List? convertedBytes,
    int? convertedSizeBytes,
    ConvertStatus? status,
    String? error,
    String? note,
    bool clearError = false,
    bool clearNote = false,
    int? width,
    int? height,
    int? sizeBytes,
    String? originalFormat,
  }) {
    return ConvertibleImage(
      id: id,
      name: name,
      path: path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      originalFormat: originalFormat ?? this.originalFormat,
      width: width ?? this.width,
      height: height ?? this.height,
      bytes: bytes ?? this.bytes,
      previewBytes: previewBytes ?? this.previewBytes,
      convertedBytes: convertedBytes ?? this.convertedBytes,
      convertedSizeBytes: convertedSizeBytes ?? this.convertedSizeBytes,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

@immutable
class FormatConverterState {
  const FormatConverterState({
    this.images = const <ConvertibleImage>[],
    this.selectedFormat = ConvertFormat.jpg,
    this.quality = 90,
    this.isConverting = false,
    this.isLoading = false,
    this.progress = 0,
    this.loadProgress = 0,
    this.loadedCount = 0,
    this.loadTotal = 0,
    this.totalConverted = 0,
    this.currentConvertingIndex = 0,
    this.totalToConvert = 0,
    this.convertingStatusText,
    this.infoMessage,
    this.errorMessage,
  });

  final List<ConvertibleImage> images;
  final ConvertFormat selectedFormat;
  final int quality;
  final bool isConverting;
  final bool isLoading;
  final double progress;
  final double loadProgress;
  final int loadedCount;
  final int loadTotal;
  final int totalConverted;
  final int currentConvertingIndex;
  final int totalToConvert;
  final String? convertingStatusText;

  /// Non-error status message (e.g. "already in JPG").
  final String? infoMessage;

  final String? errorMessage;

  int get totalImages =>
      images.where((i) => i.status != ConvertStatus.removed).length;

  int get pendingCount =>
      images.where((i) => i.isReadyToConvert || i.status == ConvertStatus.loading).length;

  int get successCount =>
      images.where((i) => i.status == ConvertStatus.success).length;

  int get failedCount =>
      images.where((i) => i.status == ConvertStatus.failed).length;

  int get skippedCount =>
      images.where((i) => i.status == ConvertStatus.skipped).length;

  bool get hasWork =>
      images.any((i) => i.isReadyToConvert);

  int get totalOriginalSize => images.fold(0, (sum, i) => sum + i.sizeBytes);

  int get totalConvertedSize =>
      images.fold(0, (sum, i) => sum + i.convertedSizeBytes);

  FormatConverterState copyWith({
    List<ConvertibleImage>? images,
    ConvertFormat? selectedFormat,
    int? quality,
    bool? isConverting,
    bool? isLoading,
    double? progress,
    double? loadProgress,
    int? loadedCount,
    int? loadTotal,
    int? totalConverted,
    int? currentConvertingIndex,
    int? totalToConvert,
    String? convertingStatusText,
    String? infoMessage,
    String? errorMessage,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return FormatConverterState(
      images: images ?? this.images,
      selectedFormat: selectedFormat ?? this.selectedFormat,
      quality: quality ?? this.quality,
      isConverting: isConverting ?? this.isConverting,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      loadProgress: loadProgress ?? this.loadProgress,
      loadedCount: loadedCount ?? this.loadedCount,
      loadTotal: loadTotal ?? this.loadTotal,
      totalConverted: totalConverted ?? this.totalConverted,
      currentConvertingIndex:
          currentConvertingIndex ?? this.currentConvertingIndex,
      totalToConvert: totalToConvert ?? this.totalToConvert,
      convertingStatusText: convertingStatusText ?? this.convertingStatusText,
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final formatConverterProvider =
    StateNotifierProvider<FormatConverterNotifier, FormatConverterState>(
  (ref) => FormatConverterNotifier(ref),
);

class FormatConverterNotifier extends StateNotifier<FormatConverterState> {
  FormatConverterNotifier(this._ref) : super(const FormatConverterState());

  final Ref _ref;

  int _idSeed = 0;
  bool _cancelRequested = false;

  void setFormat(ConvertFormat format) {
    if (state.selectedFormat == format) return;
    final updated = state.images.map((img) {
      if (img.status == ConvertStatus.success ||
          img.status == ConvertStatus.failed ||
          img.status == ConvertStatus.skipped) {
        return img.copyWith(
          status: ConvertStatus.ready,
          convertedBytes: null,
          convertedSizeBytes: 0,
          clearError: true,
          clearNote: true,
        );
      }
      return img;
    }).toList();
    state = state.copyWith(
      selectedFormat: format,
      clearInfo: true,
      images: updated,
    );
  }

  void resetStatusForReconversion() {
    final updated = state.images.map((img) {
      if (img.status == ConvertStatus.success ||
          img.status == ConvertStatus.failed ||
          img.status == ConvertStatus.skipped) {
        return img.copyWith(
          status: ConvertStatus.ready,
          convertedBytes: null,
          convertedSizeBytes: 0,
          clearError: true,
          clearNote: true,
        );
      }
      return img;
    }).toList();
    state = state.copyWith(
      images: updated,
      clearInfo: true,
    );
  }

  void setQuality(int quality) {
    state = state.copyWith(quality: quality.clamp(1, 100));
  }

  void addPickedFiles(List<PickedFile> pickedFiles) {
    final descriptors = pickedFiles
        .map((f) => <String, dynamic>{
              'name': f.name,
              'path': f.path ?? '',
              'sizeBytes': f.sizeBytes,
              'bytes': f.bytes,
            })
        .toList();
    if (descriptors.isNotEmpty) {
      unawaited(addImages(descriptors));
    }
  }

  /// Registers images immediately (so they appear in the UI) and then loads
  /// metadata, previews and dimensions progressively in the background.
  Future<void> addImages(List<Map<String, dynamic>> imageFiles) async {
    final currentCount = state.images.length;
    final maxAllowed = FileTypeDetector.maxFormatConvertImageCount;
    if (currentCount >= maxAllowed) {
      state = state.copyWith(
        errorMessage: 'Maximum limit of $maxAllowed images reached.',
        clearInfo: true,
      );
      return;
    }

    final newImages = <ConvertibleImage>[];
    var unsupportedCount = 0;
    final remainingSlots = maxAllowed - currentCount;

    for (final file in imageFiles) {
      final path = (file['path'] as String?) ?? '';
      final name = (file['name'] as String?) ?? 'image';
      final sizeBytes = (file['sizeBytes'] as int?) ?? 0;
      final bytes = file['bytes'] as Uint8List?;

      final detected = FileTypeDetector.detect(
        path: path,
        name: name,
        bytes: bytes,
      );
      if (!detected.isImage) {
        unsupportedCount++;
        continue;
      }

      if (newImages.length >= remainingSlots) {
        break;
      }

      newImages.add(
        ConvertibleImage(
          id: 'img_${_idSeed++}_${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          path: path,
          sizeBytes: sizeBytes,
          originalFormat: detected.imageFormat ?? detected.extension,
          bytes: bytes,
        ),
      );
    }

    String? notice;
    if (unsupportedCount > 0) {
      notice = unsupportedCount == 1
          ? '1 file was skipped because it is an unsupported file type.'
          : '$unsupportedCount files were skipped because they are unsupported file types.';
    }
    if (imageFiles.length - unsupportedCount > remainingSlots) {
      final limitMsg = 'Only up to $maxAllowed images can be converted at a time.';
      notice = notice != null ? '$notice $limitMsg' : limitMsg;
    }

    if (newImages.isEmpty) {
      if (notice != null) {
        state = state.copyWith(errorMessage: notice, clearInfo: true);
      }
      return;
    }

    state = state.copyWith(
      images: [...state.images, ...newImages],
      infoMessage: notice,
      clearError: true,
    );

    await _loadImages(newImages);
  }

  /// Reads bytes, probes dimensions and builds a preview for each image using
  /// bounded concurrency so the UI stays responsive and memory stays flat.
  Future<void> _loadImages(List<ConvertibleImage> imagesToLoad) async {
    if (imagesToLoad.isEmpty) return;

    for (final image in imagesToLoad) {
      _replaceImage(image.id, image.copyWith(status: ConvertStatus.loading));
    }

    state = state.copyWith(
      isLoading: true,
      loadTotal: imagesToLoad.length,
      loadedCount: 0,
      loadProgress: 0,
    );

    await ImageIsolateService.mapConcurrent<ConvertibleImage, void>(
      imagesToLoad,
      (image, index) => _loadSingleImage(image),
      concurrency: ImageIsolateService.defaultConcurrency,
      onProgress: (completed, total) {
        state = state.copyWith(
          loadedCount: completed,
          loadTotal: total,
          loadProgress: total == 0 ? 100 : (completed / total) * 100,
        );
      },
    );

    state = state.copyWith(isLoading: false, loadProgress: 100);
  }

  Future<void> _loadSingleImage(ConvertibleImage image) async {
    try {
      final bytes = await _readSourceBytes(image);
      if (bytes == null || bytes.isEmpty) {
        _replaceImage(
          image.id,
          image.copyWith(
            status: ConvertStatus.failed,
            error: 'The file could not be read.',
          ),
        );
        return;
      }

      // Trust the real header over the extension.
      final detected = FileTypeDetector.detect(
        path: image.path,
        name: image.name,
        bytes: bytes,
      );

      final probe = await ImageIsolateService.probe(bytes);
      final preview = await ImageIsolateService.thumbnail(bytes, maxSide: 360);

      _replaceImage(
        image.id,
        image.copyWith(
          bytes: image.path.isEmpty ? bytes : null,
          previewBytes: preview,
          width: probe.isValid ? probe.width : 0,
          height: probe.isValid ? probe.height : 0,
          sizeBytes: bytes.length,
          // The real header always wins over the file extension.
          originalFormat: detected.imageFormat ?? image.originalFormat,
          status: probe.isValid ? ConvertStatus.ready : ConvertStatus.failed,
          error: probe.isValid
              ? null
              : 'The file may be corrupted or unsupported.',
        ),
      );
    } catch (_) {
      _replaceImage(
        image.id,
        image.copyWith(
          status: ConvertStatus.failed,
          error: 'The file may be corrupted or unsupported.',
        ),
      );
    }
  }

  /// Converts every ready image to [state.selectedFormat].
  ///
  /// Images that already match the target codec are never re-encoded: same
  /// extension images are skipped, and same-codec/different-extension images
  /// (JPG -> JPEG) are copied so the user still gets the extension they chose.
  Future<void> convertAll() async {
    if (state.isConverting || state.isLoading) return;

    final format = state.selectedFormat;
    final candidates =
        state.images.where((i) => i.isReadyToConvert).toList(growable: false);

    if (candidates.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No images are ready to convert yet.',
        clearInfo: true,
      );
      return;
    }

    final identical = <ConvertibleImage>[];
    final renameOnly = <ConvertibleImage>[];
    final work = <ConvertibleImage>[];

    for (final image in candidates) {
      if (format.isPdf) {
        work.add(image);
        continue;
      }
      final source = FileTypeDetector.canonicalImageExtension(
        image.originalFormat,
      );
      final target = FileTypeDetector.canonicalImageExtension(format.extension);
      if (source != null && target != null && source == target) {
        if (image.name.toLowerCase().endsWith('.${format.extension}')) {
          identical.add(image);
        } else {
          renameOnly.add(image);
        }
      } else {
        work.add(image);
      }
    }

    // Nothing to re-encode for these: mark them and move on.
    for (final image in identical) {
      _replaceImage(
        image.id,
        image.copyWith(
          status: ConvertStatus.skipped,
          note: 'Already ${format.label}',
        ),
      );
    }

    final info = _buildInfoMessage(identical.length, renameOnly.length, format);

    if (work.isEmpty && renameOnly.isEmpty) {
      state = state.copyWith(
        isConverting: false,
        progress: 100,
        totalConverted: 0,
        totalToConvert: 0,
        currentConvertingIndex: 0,
        convertingStatusText: null,
        infoMessage: info,
        clearError: true,
      );
      return;
    }

    _cancelRequested = false;
    state = state.copyWith(
      isConverting: true,
      progress: 0,
      totalConverted: 0,
      totalToConvert: work.length,
      currentConvertingIndex: work.isEmpty ? 0 : 1,
      convertingStatusText: work.isEmpty
          ? 'Finalising...'
          : 'Converting image 1 of ${work.length}...',
      infoMessage: info,
      clearError: true,
    );

    var written = 0;

    // Same codec, different extension: copy the bytes, never re-encode.
    for (final image in renameOnly) {
      if (_cancelRequested) break;
      final bytes = await _readSourceBytes(image);
      if (bytes == null) {
        _replaceImage(
          image.id,
          image.copyWith(
            status: ConvertStatus.failed,
            error: 'The file could not be read.',
          ),
        );
        continue;
      }
      _replaceImage(
        image.id,
        image.copyWith(
          convertedBytes: bytes,
          convertedSizeBytes: bytes.length,
          status: ConvertStatus.success,
          note: 'Extension changed only',
        ),
      );
      written++;
    }

    if (work.isNotEmpty) {
      await ImageIsolateService.mapConcurrent<ConvertibleImage, void>(
        work,
        (image, index) => _convertSingleImage(image, format),
        concurrency: ImageIsolateService.defaultConcurrency,
        isCancelled: () => _cancelRequested,
        onProgress: (completed, total) {
          state = state.copyWith(
            totalConverted: completed,
            currentConvertingIndex: completed,
            progress: total == 0 ? 100 : (completed / total) * 100,
            convertingStatusText: completed >= total
                ? 'Completed'
                : 'Converted $completed of $total...',
          );
        },
      );
    }

    final cancelled = _cancelRequested;
    _cancelRequested = false;

    state = state.copyWith(
      isConverting: false,
      progress: cancelled ? state.progress : 100,
      convertingStatusText: cancelled
          ? 'Cancelled'
          : 'Converted $written of ${work.length} images',
      infoMessage: cancelled ? 'Conversion cancelled.' : info,
    );
  }

  /// Requests cancellation of an in-flight conversion.
  ///
  /// Work already finished is kept; queued images stay pending so the user can
  /// resume by tapping convert again.
  void cancelConversion() {
    if (!state.isConverting) return;
    _cancelRequested = true;
    state = state.copyWith(convertingStatusText: 'Cancelling...');
  }

  Future<void> _convertSingleImage(
    ConvertibleImage image,
    ConvertFormat format,
  ) async {
    if (_cancelRequested) return;

    final source = await _readSourceBytes(image);
    if (source == null || source.isEmpty) {
      _replaceImage(
        image.id,
        image.copyWith(
          status: ConvertStatus.failed,
          error: 'The file could not be read.',
        ),
      );
      return;
    }

    _replaceImage(image.id, image.copyWith(status: ConvertStatus.converting));

    try {
      final settings = _ref.read(appSettingsProvider);
      if (WatermarkHelper.cachedIconBytes == null) {
        await WatermarkHelper.loadIconBytes();
      }

      Uint8List? converted;
      if (format == ConvertFormat.webp && Platform.isAndroid) {
        var imageToEncode = source;
        final enableWatermark = settings.enableGlobalWatermark;
        if (enableWatermark) {
          var decoded = img.decodeImage(source);
          if (decoded != null) {
            decoded = WatermarkHelper.applyToImage(
              decoded,
              settings,
              iconBytes: WatermarkHelper.cachedIconBytes,
            );
            imageToEncode = Uint8List.fromList(img.encodePng(decoded));
          }
        }
        converted = await PlatformImageEncoder.encodeWebP(
          imageToEncode,
          quality: state.quality,
        );
      }

      converted ??= await compute(_convertWorker, <String, Object?>{
        'source': source,
        'target': format.codec,
        'quality': state.quality,
        'settings': settings,
        'iconBytes': WatermarkHelper.cachedIconBytes,
      });

      if (converted == null || converted.isEmpty) {
        _replaceImage(
          image.id,
          image.copyWith(
            status: ConvertStatus.failed,
            error: 'The file may be corrupted or unsupported.',
          ),
        );
        return;
      }

      _replaceImage(
        image.id,
        image.copyWith(
          convertedBytes: converted,
          convertedSizeBytes: converted.length,
          status: ConvertStatus.success,
        ),
      );
    } on OutOfMemoryError {
      _replaceImage(
        image.id,
        image.copyWith(
          status: ConvertStatus.failed,
          error: 'Not enough memory to process this image.',
        ),
      );
    } catch (_) {
      _replaceImage(
        image.id,
        image.copyWith(
          status: ConvertStatus.failed,
          error: 'The file may be corrupted or unsupported.',
        ),
      );
    }
  }

  Future<Uint8List?> _readSourceBytes(ConvertibleImage image) async {
    if (image.bytes != null && image.bytes!.isNotEmpty) return image.bytes;
    if (image.path.isEmpty) return null;
    try {
      final file = File(image.path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String? _buildInfoMessage(
    int identical,
    int renameOnly,
    ConvertFormat format,
  ) {
    final parts = <String>[];
    if (identical > 0) {
      parts.add(
        identical == 1
            ? '1 image is already ${format.label} and was not converted.'
            : '$identical images are already ${format.label} and were not converted.',
      );
    }
    if (renameOnly > 0) {
      parts.add(
        renameOnly == 1
            ? '1 image was copied to .${format.extension} without re-encoding.'
            : '$renameOnly images were copied to .${format.extension} without re-encoding.',
      );
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// Replaces one image by id, leaving every other entry untouched so a
  /// progress update cannot clobber concurrent work.
  void _replaceImage(String id, ConvertibleImage replacement) {
    if (!mounted) return;
    final index = state.images.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final updated = [...state.images];
    updated[index] = replacement;
    state = state.copyWith(images: updated);
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final updated = [...state.images]..removeAt(index);
    state = state.copyWith(images: updated);
  }

  void clearAll() {
    _cancelRequested = false;
    state = const FormatConverterState();
  }

  void resetFailed() {
    final updated = state.images.map((image) {
      if (image.status == ConvertStatus.failed) {
        return image.copyWith(status: ConvertStatus.ready, error: null);
      }
      if (image.status == ConvertStatus.skipped) {
        return image.copyWith(status: ConvertStatus.ready, error: null);
      }
      return image;
    }).toList();
    state = state.copyWith(images: updated, clearError: true, clearInfo: true);
  }
}

// ─── Isolate worker ─────────────────────────────────────────────────────────

/// Decodes, optionally watermarks, and encodes one image. Runs off the UI
/// isolate so multi-image conversion never freezes the app.
Future<Uint8List?> _convertWorker(Map<String, Object?> params) async {
  final source = params['source'] as Uint8List;
  final target = (params['target'] as String).toLowerCase();
  final quality = (params['quality'] as num?)?.toInt() ?? 90;
  final settings = params['settings'] as AppSettingsState?;
  final iconBytes = params['iconBytes'] as Uint8List?;

  var decoded = img.decodeImage(source);
  if (decoded == null) return null;

  try {
    decoded.exif.clear();
  } catch (_) {
    // Not every decoder carries EXIF.
  }

  final enableWatermark = settings?.enableGlobalWatermark ?? false;
  if (enableWatermark && settings != null && target != 'pdf') {
    decoded = WatermarkHelper.applyToImage(
      decoded,
      settings,
      iconBytes: iconBytes,
    );
  }

  if (target == 'pdf') {
    return _buildPdf(source, decoded, settings, iconBytes);
  }

  if (target == 'jpg' || target == 'jpeg' || target == 'bmp' || target == 'tif' || target == 'tiff') {
    decoded = _flattenAlpha(decoded);
  }

  final List<int> encoded;
  switch (target) {
    case 'jpg':
    case 'jpeg':
      encoded = img.encodeJpg(decoded, quality: quality.clamp(1, 100));
      break;
    case 'png':
      encoded = img.encodePng(decoded);
      break;
    case 'bmp':
      encoded = img.encodeBmp(decoded);
      break;
    case 'tif':
    case 'tiff':
      encoded = img.encodeTiff(decoded);
      break;
    case 'webp':
      encoded = img.encodeWebP(
        decoded,
        lossless: quality >= 100,
        quality: quality.clamp(1, 100),
      );
      break;
    default:
      return null;
  }
  return Uint8List.fromList(encoded);
}

Future<Uint8List> _buildPdf(
  Uint8List sourceBytes,
  img.Image decoded,
  AppSettingsState? settings,
  Uint8List? iconBytes,
) async {
  final pdf = pw.Document();
  final pdfImage = pw.MemoryImage(sourceBytes);
  final enableWatermark = settings?.enableGlobalWatermark ?? false;
  if (enableWatermark && iconBytes != null && iconBytes.isNotEmpty) {
    WatermarkHelper.setIconBytes(iconBytes);
  }

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      ),
      margin: pw.EdgeInsets.zero,
      build: (pw.Context context) {
        final content = pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
        );

        if (enableWatermark && settings != null) {
          return pw.Stack(
            children: [
              content,
              WatermarkHelper.buildPdfWatermarkWidget(
                iconBytes: iconBytes,
                text: settings.watermarkText,
                colorHex: settings.watermarkColorHex,
                opacity: settings.watermarkOpacity,
                positionIndex: settings.watermarkPositionIndex,
                useAppLogo: settings.useWatermarkLogo,
              ),
            ],
          );
        }

        return content;
      },
    ),
  );
  return pdf.save();
}

img.Image _flattenAlpha(img.Image image) {
  if (!image.hasAlpha) return image;
  final flattened = img.Image(width: image.width, height: image.height);
  img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flattened, image);
  return flattened;
}

/// Formats a byte count for the converter UI.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
