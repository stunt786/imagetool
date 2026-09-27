import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/models/operation_folder.dart';
import '../../../core/services/operation_recorder.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/pdf_compress_state.dart';

final pdfCompressProvider =
    NotifierProvider<PdfCompressNotifier, PdfCompressState>(
  PdfCompressNotifier.new,
);

class PdfCompressNotifier extends Notifier<PdfCompressState> {
  final _manager = PrivateToPublicPdfManager();

  /// The Syncfusion watermark pass holds the whole document in memory, so it is
  /// only applied to documents that comfortably fit. Larger documents are still
  /// compressed, the watermark is skipped and the reason is surfaced in the UI.
  static const int _watermarkPageLimit = 400;

  /// The raster fallback renders every page and loses the text layer, so it is
  /// reserved for small documents whose embedded images cannot be decoded by
  /// the compression engine (JPEG 2000 / JBIG2 / CCITT).
  static const int _rasterPageLimit = 24;
  static const int _rasterInputLimit = 25 * 1024 * 1024;

  @override
  PdfCompressState build() => const PdfCompressState();

  /// Picks a single PDF file and copies it into the sandbox cache.
  Future<void> pickFile(BuildContext context) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.pdfs,
      allowMultiple: false,
    );

    if (picked.isEmpty) return;

    final file = picked.first;
    if (file.bytes == null && file.path == null) {
      state = state.copyWith(errorMessage: 'Could not read the selected file');
      return;
    }

    try {
      final sandboxPath = await _manager.importPickedFile(file);

      // Trust the file on disk rather than the picker metadata so the reported
      // compression ratio is always accurate.
      var size = file.sizeBytes;
      try {
        size = await File(sandboxPath).length();
      } catch (_) {}

      state = state.copyWith(
        selectedFilePath: sandboxPath,
        selectedFileName: file.name,
        selectedFileSize: size,
        errorMessage: null,
        note: null,
        outputPath: null,
        outputFileSize: null,
        publicExportPath: null,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to access file: $e');
    }
  }

  /// Sets the compression level.
  void setCompressionLevel(CompressionLevel level) {
    state = state.copyWith(compressionLevel: level);
  }

  /// Compresses the selected PDF file and returns the path to the result.
  ///
  /// The heavy lifting happens in a background isolate using a memory-safe
  /// engine that re-encodes embedded images and DEFLATEs uncompressed streams.
  /// The output is never larger than the input: when no reduction is possible
  /// the original bytes are copied and the UI says so.
  Future<String?> compress() async {
    if (!state.hasFile) {
      state = state.copyWith(errorMessage: 'No file selected');
      return null;
    }

    final inputPath = state.selectedFilePath!;
    final selectedName = state.selectedFileName ?? 'compressed';
    final quality = state.compressionLevel.qualityFactor;
    final appSettings = ref.read(appSettingsProvider);
    final applyWatermark = appSettings.enableGlobalWatermark;

    var inputSize = state.selectedFileSize ?? 0;
    try {
      inputSize = await File(inputPath).length();
    } catch (_) {}

    state = state.copyWith(
      isProcessing: true,
      progress: 0.0,
      errorMessage: null,
      note: null,
      outputPath: null,
      outputFileSize: null,
      publicExportPath: null,
    );

    final saveDir =
        await ref.read(appSettingsProvider.notifier).getSaveDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final baseName = _pdfBaseName(selectedName);
    final outputPath =
        '${saveDir.path}/pixeltools_${baseName}_compressed_$timestamp.pdf';
    final workingPath = '${saveDir.path}/.pixeltools_work_$timestamp.pdf';
    final watermarkedPath = '${saveDir.path}/.pixeltools_wm_$timestamp.pdf';

    String? note;

    try {
      // 1) Real compression, off the UI thread.
      final outcome = await PdfService.compressPdfFile(
        inputPath: inputPath,
        outputPath: workingPath,
        quality: quality,
        onProgress: (progress) {
          if (state.selectedFilePath == inputPath) {
            state = state.copyWith(progress: 0.05 + progress * 0.8);
          }
        },
      );
      if (state.selectedFilePath != inputPath) return null;

      note = outcome.note;
      var finalPath = workingPath;
      var didImprove = outcome.improved;

      // 2) Last-resort raster fallback: only when the engine found images it
      //    could not decode and the document is small enough to render safely.
      if (!didImprove &&
          outcome.imagesUnsupported > 0 &&
          outcome.pageCount > 0 &&
          outcome.pageCount <= _rasterPageLimit &&
          inputSize <= _rasterInputLimit) {
        state = state.copyWith(progress: 0.82);
        final raster = await PdfService.instance.rasterCompressPdf(
          inputPath: inputPath,
          inputLength: inputSize,
          quality: quality,
          onProgress: (progress) {
            if (state.selectedFilePath == inputPath) {
              state = state.copyWith(progress: 0.82 + progress * 0.1);
            }
          },
        );
        if (state.selectedFilePath != inputPath) return null;
        if (raster != null && raster.length < inputSize) {
          await File(workingPath).writeAsBytes(raster, flush: true);
          didImprove = true;
          note = 'Pages were re-rendered as images to reduce the size; '
              'text in the result is no longer selectable.';
        }
      }

      // 3) Optional global watermark, applied to the already compressed file.
      if (applyWatermark && didImprove) {
        if (outcome.pageCount > _watermarkPageLimit) {
          note = 'Watermark skipped for this very large document.';
        } else {
          state = state.copyWith(progress: 0.9);
          try {
            if (WatermarkHelper.cachedIconBytes == null) {
              await WatermarkHelper.loadIconBytes();
            }
            final compressedBytes = await File(workingPath).readAsBytes();
            final watermarked = await PdfService.watermarkPdfBytes(
              inputBytes: compressedBytes,
              text: appSettings.watermarkText,
              colorHex: appSettings.watermarkColor,
              opacity: appSettings.watermarkOpacity,
              positionIndex: appSettings.watermarkPosition,
              useAppLogo: appSettings.useWatermarkLogo,
              iconBytes: WatermarkHelper.cachedIconBytes,
            );
            if (watermarked != null &&
                watermarked.isNotEmpty &&
                watermarked.length < inputSize) {
              await File(watermarkedPath).writeAsBytes(watermarked, flush: true);
              finalPath = watermarkedPath;
            } else if (watermarked != null && watermarked.isNotEmpty) {
              note = 'Watermark skipped: it would have produced a larger file.';
            }
          } catch (_) {
            note = 'Compression finished, but the watermark could not be applied.';
          }
        }
      }

      if (state.selectedFilePath != inputPath) return null;
      state = state.copyWith(progress: 0.97);

      // 4) Publish the result.
      final outputFile = File(outputPath);
      await File(finalPath).copy(outputPath);

      final outputFileSize = await outputFile.length();
      if (!await outputFile.exists() || outputFileSize == 0) {
        throw Exception('Compressed PDF file was not created or is empty');
      }

      if (!didImprove && note == null) {
        note = 'This PDF is already highly optimised; the original file was kept.';
      }

      // Group the compressed output in Files.
      await recordCompletedOperation(
        ref.read(operationStoreProvider),
        OperationKind.pdfCompress,
        [outputPath],
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        selectedFileSize: inputSize,
        outputPath: outputPath,
        outputFileSize: outputFileSize,
        publicExportPath: outputPath,
        note: note,
      );

      return outputPath;
    } catch (e) {
      await _manager.cleanup();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Compression failed: $e',
      );
      return null;
    } finally {
      await _deleteQuietly(workingPath);
      await _deleteQuietly(watermarkedPath);
    }
  }

  /// Exports the compressed file from the sandbox to a user-chosen public
  /// directory via the Storage Access Framework (SAF).
  Future<String?> exportFile() async {
    if (state.outputPath == null) return null;

    try {
      final resultPath = await _manager.exportSingleFile(
        sandboxPath: state.outputPath!,
        suggestedName:
            'pixeltools_${_pdfBaseName(state.selectedFileName)}_compressed.pdf',
      );

      if (resultPath != null) {
        state = state.copyWith(publicExportPath: resultPath);
      }

      return resultPath;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Export failed: $e');
      return null;
    } finally {
      await _manager.cleanup();
    }
  }

  /// Clears the current selection and results, cleaning the sandbox.
  void clear() {
    _manager.cleanup();
    state = state.reset();
  }

  /// Clears only the error message.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup only.
    }
  }

  String _pdfBaseName(String? name) {
    final value = name ?? 'compressed';
    final dot = value.lastIndexOf('.');
    return dot > 0 ? value.substring(0, dot) : value;
  }
}
