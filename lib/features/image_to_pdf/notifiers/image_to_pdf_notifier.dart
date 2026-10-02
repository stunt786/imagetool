import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/models/operation_folder.dart';
import '../../../core/services/image_isolate_service.dart';
import '../../../core/services/operation_recorder.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/utils/file_type_detector.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/image_to_pdf_state.dart';

final imageToPdfProvider =
    NotifierProvider<ImageToPdfNotifier, ImageToPdfState>(
  ImageToPdfNotifier.new,
);

class ImageToPdfNotifier extends Notifier<ImageToPdfState> {
  int _idSeed = 0;
  bool _cancelRequested = false;
  bool _disposed = false;

  /// Aggregated load counters so that adding files one at a time still shows
  /// honest "Loading images X of Y" progress.
  int _loadTotal = 0;
  int _loadCompleted = 0;

  @override
  ImageToPdfState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const ImageToPdfState(
      images: [],
      pageSettings: PdfPageSettings.defaults,
    );
  }

  /// Writes state only while the provider is alive; background work may finish
  /// after the screen is gone.
  void _emit(ImageToPdfState next) {
    if (_disposed) return;
    state = next;
  }

  /// Picks images and registers them immediately, then prepares previews and
  /// dimensions in the background so the list appears instantly.
  Future<void> pickImages(BuildContext context) async {
    final currentCount = state.images.length;
    final maxAllowed = FileTypeDetector.maxImageToPdfCount;
    if (currentCount >= maxAllowed) {
      state = state.copyWith(
        errorMessage: 'Maximum limit of $maxAllowed images reached.',
        clearGeneratedPath: true,
      );
      return;
    }

    final remaining = maxAllowed - currentCount;
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.images,
      allowMultiple: true,
      maxAssets: remaining,
    );

    if (picked.isEmpty) return;

    final newItems = <ImageToPdfItem>[];
    var unsupportedCount = 0;

    for (final file in picked) {
      final hasPath = (file.path ?? '').isNotEmpty;
      final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
      if (!hasPath && !hasBytes) continue;

      final detected = FileTypeDetector.detect(
        path: file.path,
        name: file.name,
        bytes: file.bytes,
      );
      if (!detected.isImage) {
        unsupportedCount++;
        continue;
      }

      if (newItems.length >= remaining) {
        break;
      }

      newItems.add(
        ImageToPdfItem(
          id: _nextId(),
          path: file.path ?? '',
          name: file.name,
          sizeBytes: file.sizeBytes,
          // Only hold bytes when we cannot re-read the file later.
          imageBytes: hasPath ? null : file.bytes,
          isLoading: true,
        ),
      );
    }

    String? notice;
    if (unsupportedCount > 0) {
      notice = unsupportedCount == 1
          ? '1 file was skipped because it is an unsupported file type.'
          : '$unsupportedCount files were skipped because they are unsupported file types.';
    }
    if (picked.length - unsupportedCount > remaining) {
      final limitMsg = 'Only up to $maxAllowed images can be converted to PDF at a time.';
      notice = notice != null ? '$notice $limitMsg' : limitMsg;
    }

    if (newItems.isEmpty) {
      state = state.copyWith(
        errorMessage: notice ?? 'None of the selected files could be read.',
        clearGeneratedPath: true,
      );
      return;
    }

    state = state.copyWith(
      images: [...state.images, ...newItems],
      errorMessage: notice,
      clearGeneratedPath: true,
    );

    unawaited(_loadItems(newItems));
  }

  Future<void> addImageFromPath(String path) async {
    final maxAllowed = FileTypeDetector.maxImageToPdfCount;
    if (state.images.length >= maxAllowed) {
      state = state.copyWith(
        errorMessage: 'Maximum limit of $maxAllowed images reached.',
        clearGeneratedPath: true,
      );
      return;
    }

    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    final exists = await file.exists();
    final sizeBytes = exists ? await file.length() : 0;

    final detected = FileTypeDetector.detect(path: path, name: name);
    if (!detected.isImage) {
      state = state.copyWith(
        errorMessage: 'The selected file is not a supported image format.',
        clearGeneratedPath: true,
      );
      return;
    }

    final newItem = ImageToPdfItem(
      id: _nextId(),
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      isLoading: exists,
      errorMessage: exists ? null : 'The file could not be found.',
    );

    state = state.copyWith(
      images: [...state.images, newItem],
      clearError: true,
      clearGeneratedPath: true,
    );

    if (exists) unawaited(_loadItems([newItem]));
  }

  Future<void> addImageFromBytes({
    required Uint8List bytes,
    required String name,
    String? path,
  }) async {
    final maxAllowed = FileTypeDetector.maxImageToPdfCount;
    if (state.images.length >= maxAllowed) {
      state = state.copyWith(
        errorMessage: 'Maximum limit of $maxAllowed images reached.',
        clearGeneratedPath: true,
      );
      return;
    }

    final detected = FileTypeDetector.detect(path: path, name: name, bytes: bytes);
    if (!detected.isImage) {
      state = state.copyWith(
        errorMessage: 'The selected file is not a supported image format.',
        clearGeneratedPath: true,
      );
      return;
    }

    final hasPath = (path ?? '').isNotEmpty;
    final newItem = ImageToPdfItem(
      id: _nextId(),
      path: path ?? '',
      name: name,
      sizeBytes: bytes.length,
      imageBytes: hasPath ? null : bytes,
      isLoading: true,
    );

    state = state.copyWith(
      images: [...state.images, newItem],
      clearError: true,
      clearGeneratedPath: true,
    );

    unawaited(_loadItems([newItem]));
  }

  /// Reads, probes and previews [items] with bounded concurrency so picking
  /// twenty photos cannot freeze the app or blow up memory.
  Future<void> _loadItems(List<ImageToPdfItem> items) async {
    if (items.isEmpty) return;

    // Start a fresh counter only once the previous work has drained.
    if (_loadCompleted >= _loadTotal) {
      _loadTotal = 0;
      _loadCompleted = 0;
    }
    _loadTotal += items.length;

    _emit(state.copyWith(
      isLoadingImages: true,
      loadTotal: _loadTotal,
      loadedCount: _loadCompleted,
      loadProgress:
          _loadTotal == 0 ? 0 : (_loadCompleted / _loadTotal) * 100,
    ));

    await ImageIsolateService.mapConcurrent<ImageToPdfItem, void>(
      items,
      (item, index) async {
        final bytes = await _readItemBytes(item);
        if (bytes == null || bytes.isEmpty) {
          _updateItem(
            item.id,
            item.copyWith(
              isLoading: false,
              errorMessage: 'The file could not be read.',
            ),
          );
          return;
        }

        final res =
            await ImageIsolateService.probeAndThumbnail(bytes, maxSide: 320);

        _updateItem(
          item.id,
          item.copyWith(
            previewBytes: res.thumbnail,
            width: res.isValid ? res.width : null,
            height: res.isValid ? res.height : null,
            sizeBytes: bytes.length,
            isLoading: false,
            clearError: res.isValid,
            errorMessage: res.isValid
                ? null
                : 'The image may be corrupted or unsupported.',
          ),
        );
      },
      concurrency: ImageIsolateService.defaultConcurrency,
      onProgress: (completed, total) {
        _loadCompleted++;
        _emit(state.copyWith(
          loadedCount: _loadCompleted,
          loadTotal: _loadTotal,
          loadProgress: _loadTotal == 0
              ? 100
              : (_loadCompleted / _loadTotal * 100).clamp(0, 100),
        ));
      },
    );

    if (_loadCompleted >= _loadTotal) {
      _emit(state.copyWith(isLoadingImages: false, loadProgress: 100));
    }
  }

  String _nextId() => 'img_pdf_${_idSeed++}';

  Future<Uint8List?> _readItemBytes(ImageToPdfItem item) async {
    final inMemory = item.imageBytes;
    if (inMemory != null && inMemory.isNotEmpty) return inMemory;
    if (item.path.isEmpty) return null;
    try {
      final file = File(item.path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  void _updateItem(String id, ImageToPdfItem replacement) {
    _emit(state.replaceImageById(id, replacement));
  }

  void removeImage(int index) {
    state = state.removeImage(index);
  }

  void swapImage(int index1, int index2) {
    state = state.swapImages(index1, index2);
  }

  void reorderImages(int oldIndex, int newIndex) {
    state = state.reorderImages(oldIndex, newIndex);
  }

  void updatePageSettings(PdfPageSettings settings) {
    state = state.copyWith(pageSettings: settings);
  }

  void clearAll() {
    _cancelRequested = false;
    state = const ImageToPdfState(
      images: [],
      pageSettings: PdfPageSettings.defaults,
    );
  }

  /// Requests cancellation of an in-flight PDF build.
  ///
  /// Nothing is written to disk until every page has been prepared, so
  /// cancelling can never leave a partial PDF behind.
  void cancelGeneration() {
    if (!state.isGenerating) return;
    _cancelRequested = true;
    state = state.copyWith(statusText: 'Cancelling...', canCancel: false);
  }

  /// Builds the PDF, preparing each page on a background isolate and reporting
  /// real per-image progress.
  Future<String?> generatePdf() async {
    if (state.images.isEmpty) {
      state = state.copyWith(errorMessage: 'No images selected');
      return null;
    }
    if (state.isLoadingImages) {
      state = state.copyWith(
        errorMessage: 'Please wait for the images to finish loading.',
      );
      return null;
    }

    _cancelRequested = false;
    final settings = state.pageSettings;
    final appSettings = ref.read(appSettingsProvider);
    final items = List<ImageToPdfItem>.from(state.images);
    final total = items.length;

    // Every run is one operation, so its outputs stay grouped in Files.
    OperationSession? session;
    try {
      session = await OperationRecorder(ref.read(operationStoreProvider))
          .start(OperationKind.imageToPdf, expectedItems: 1);
    } catch (_) {
      session = null;
    }

    state = state.copyWith(
      isGenerating: true,
      canCancel: true,
      progress: 0.0,
      statusText: 'Preparing images...',
      clearError: true,
      clearGeneratedPath: true,
    );

    try {
      if (WatermarkHelper.cachedIconBytes == null) {
        await WatermarkHelper.loadIconBytes();
      }

      final pdf = pw.Document();
      var addedPages = 0;

      _emit(state.copyWith(
        statusText: 'Adding image 1 of $total',
        progress: 0.0,
      ));

      if (_cancelRequested) {
        await session?.cancel();
        state = state.copyWith(
          isGenerating: false,
          canCancel: false,
          progress: 0,
          statusText: 'Cancelled',
        );
        return null;
      }

      final preparedPages =
          await ImageIsolateService.mapConcurrent<ImageToPdfItem, _PreparedPage?>(
        items,
        (item, index) async {
          if (_cancelRequested) return null;
          final source = await _readItemBytes(item);
          if (source == null || source.isEmpty || _cancelRequested) return null;

          final params = <String, Object?>{
            'bytes': source,
            'optimized': settings.quality == PdfQuality.optimized,
            'quality': 90,
          };
          if (Platform.environment.containsKey('FLUTTER_TEST')) {
            return _preparePageWorker(params);
          }
          return await compute(_preparePageWorker, params);
        },
        concurrency: ImageIsolateService.defaultConcurrency,
        onProgress: (completed, totalCount) {
          _emit(state.copyWith(
            statusText: 'Adding image ${completed.clamp(1, totalCount)} of $totalCount',
            progress: (completed / totalCount) * 0.7,
          ));
        },
        isCancelled: () => _cancelRequested,
      );

      if (_cancelRequested) {
        await session?.cancel();
        state = state.copyWith(
          isGenerating: false,
          canCancel: false,
          progress: 0,
          statusText: 'Cancelled',
        );
        return null;
      }

      for (var i = 0; i < preparedPages.length; i++) {
        if (_cancelRequested) break;
        final prepared = preparedPages[i];
        if (prepared == null) continue;

        _emit(state.copyWith(
          statusText: 'Adding image ${i + 1} of $total',
          progress: 0.7 + (((i + 1) / preparedPages.length) * 0.2),
        ));
        if (_cancelRequested) break;

        final imageWidth = prepared.width;
        final imageHeight = prepared.height;
        final isImageLandscape = imageWidth > imageHeight;

        PdfPageFormat pageFormat;
        switch (settings.pageSize) {
          case PdfPageSize.a4:
            pageFormat = PdfPageFormat.a4;
            break;
          case PdfPageSize.a3:
            pageFormat = PdfPageFormat.a3;
            break;
          case PdfPageSize.usLetter:
            pageFormat = PdfPageFormat.letter;
            break;
          case PdfPageSize.usLegal:
            pageFormat = PdfPageFormat.legal;
            break;
          case PdfPageSize.matchImage:
            const pointsPerPixel = 72.0 / 150.0;
            pageFormat = PdfPageFormat(
              imageWidth * pointsPerPixel,
              imageHeight * pointsPerPixel,
            );
            break;
        }

        if (settings.orientation == PdfOrientation.auto) {
          final isPagePortrait = pageFormat.width < pageFormat.height;
          if (isImageLandscape && isPagePortrait) {
            pageFormat = pageFormat.landscape;
          } else if (!isImageLandscape && !isPagePortrait) {
            pageFormat = pageFormat.portrait;
          }
        } else if (settings.orientation == PdfOrientation.landscape) {
          pageFormat = pageFormat.landscape;
        } else {
          pageFormat = pageFormat.portrait;
        }

        final marginLeft = settings.marginLeft * PdfPageFormat.inch;
        final marginRight = settings.marginRight * PdfPageFormat.inch;
        final marginTop = settings.marginTop * PdfPageFormat.inch;
        final marginBottom = settings.marginBottom * PdfPageFormat.inch;
        final availableFormat = PdfPageFormat(
          pageFormat.width - marginLeft - marginRight,
          pageFormat.height - marginTop - marginBottom,
        );

        final pdfImage = pw.MemoryImage(prepared.bytes);

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (context) {
              final content = pw.Container(
                padding: pw.EdgeInsets.only(
                  left: marginLeft,
                  top: marginTop,
                  right: marginRight,
                  bottom: marginBottom,
                ),
                child: _buildImageWidget(
                  pdfImage,
                  settings.fitMode,
                  availableFormat,
                  imageWidth,
                  imageHeight,
                ),
              );

              if (appSettings.enableGlobalWatermark) {
                return pw.Stack(
                  children: [
                    content,
                    WatermarkHelper.buildPdfWatermarkWidget(
                      iconBytes: WatermarkHelper.cachedIconBytes,
                      text: appSettings.watermarkText,
                      colorHex: appSettings.watermarkColor,
                      opacity: appSettings.watermarkOpacity,
                      positionIndex: appSettings.watermarkPosition,
                      useAppLogo: appSettings.useWatermarkLogo,
                    ),
                  ],
                );
              }
              return content;
            },
          ),
        );

        addedPages++;
      }

      if (_cancelRequested) {
        await session?.cancel();
        state = state.copyWith(
          isGenerating: false,
          canCancel: false,
          progress: 0,
          statusText: 'Cancelled',
        );
        return null;
      }

      if (addedPages == 0) {
        throw StateError('None of the selected images could be read.');
      }

      state = state.copyWith(
        statusText: 'Saving PDF...',
        progress: 0.95,
        canCancel: false,
      );

      final pdfBytes = await pdf.save();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final firstName = items.first.name;
      final dot = firstName.lastIndexOf('.');
      final baseName = dot > 0 ? firstName.substring(0, dot) : firstName;
      final fileName = '${baseName}_$timestamp.pdf';

      String outputPath;
      if (session != null) {
        // Saving inside the operation folder keeps Files grouped and never
        // overwrites a previous result.
        final target = await ref
            .read(operationStoreProvider)
            .resolveOutputPath(session.directory, fileName);
        final file = File(target);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(pdfBytes, flush: true);
        outputPath = target;
        await session.recordFile(target, pageCount: addedPages);
        await session.complete();
      } else {
        // Fallback: keep the previous behaviour if the store is unavailable.
        final saveDir =
            await ref.read(appSettingsProvider.notifier).getSaveDirectory();
        outputPath = path.join(saveDir.path, 'pixeltools_$fileName');
        await File(outputPath).writeAsBytes(pdfBytes, flush: true);
      }

      final fileSize = await File(outputPath).length();
      if (!await File(outputPath).exists() || fileSize == 0) {
        throw Exception('PDF file was not created or is empty');
      }

      // Export to public storage (MediaStore Download/PixelTools or custom SAF folder)
      try {
        await PublicStorage.publishFile(
          sourcePath: outputPath,
          fileName: fileName,
          kind: PublicFileKind.document,
        );
      } catch (_) {
        // Local copy in OperationStore remains available
      }

      state = state.copyWith(
        isGenerating: false,
        progress: 1.0,
        statusText: 'Completed',
        generatedPdfPath: outputPath,
      );

      return outputPath;
    } catch (e) {
      await session?.fail('Image to PDF failed: $e');
      state = state.copyWith(
        isGenerating: false,
        canCancel: false,
        clearStatus: true,
        errorMessage: 'Failed to generate PDF: $e',
      );
      return null;
    }
  }

  pw.Widget _buildImageWidget(
    pw.MemoryImage image,
    ImageFitMode fitMode,
    PdfPageFormat availableFormat,
    int imageWidth,
    int imageHeight,
  ) {
    switch (fitMode) {
      case ImageFitMode.fit:
        return pw.Image(
          image,
          fit: pw.BoxFit.contain,
          width: availableFormat.width,
          height: availableFormat.height,
        );
      case ImageFitMode.fill:
        return pw.Image(
          image,
          fit: pw.BoxFit.cover,
          width: availableFormat.width,
          height: availableFormat.height,
        );
      case ImageFitMode.center:
        final scaleX = availableFormat.width / imageWidth;
        final scaleY = availableFormat.height / imageHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final displayScale = scale < 1.0 ? scale : 1.0;
        return pw.Center(
          child: pw.Image(
            image,
            width: imageWidth * displayScale,
            height: imageHeight * displayScale,
          ),
        );
      case ImageFitMode.stretch:
        return pw.Image(
          image,
          fit: pw.BoxFit.fill,
          width: availableFormat.width,
          height: availableFormat.height,
        );
    }
  }
}

/// A page image that has been decoded, normalised and is ready to embed.
@immutable
class _PreparedPage {
  const _PreparedPage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Decodes an image and returns embeddable bytes plus its real dimensions.
///
/// Runs in a background isolate. Normalising here also removes a latent bug
/// where WebP/BMP/TIFF sources were passed straight to `pw.MemoryImage`.
_PreparedPage? _preparePageWorker(Map<String, Object?> params) {
  final source = params['bytes'] as Uint8List;
  final optimized = params['optimized'] as bool? ?? true;
  final quality = (params['quality'] as num?)?.toInt() ?? 90;
  final format = FileTypeDetector.imageFormatFromSignature(source);

  // If not optimizing and already jpg or png, probe dimensions quickly without full re-encode
  if (!optimized && (format == 'jpg' || format == 'png')) {
    final info = img.decodeImage(source);
    if (info == null) return null;
    return _PreparedPage(
      bytes: source,
      width: info.width,
      height: info.height,
    );
  }

  var decoded = img.decodeImage(source);
  if (decoded == null) return null;

  // Cap maximum dimension to 2400 for speed and memory efficiency when optimizing
  if (optimized && (decoded.width > 2400 || decoded.height > 2400)) {
    if (decoded.width >= decoded.height) {
      decoded = img.copyResize(decoded, width: 2400);
    } else {
      decoded = img.copyResize(decoded, height: 2400);
    }
  }

  Uint8List output;
  if (optimized) {
    output = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  } else if (decoded.hasAlpha) {
    final flattened = img.Image(width: decoded.width, height: decoded.height);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, decoded);
    output = Uint8List.fromList(img.encodePng(flattened));
  } else {
    output = Uint8List.fromList(img.encodePng(decoded));
  }

  return _PreparedPage(
    bytes: output,
    width: decoded.width,
    height: decoded.height,
  );
}
