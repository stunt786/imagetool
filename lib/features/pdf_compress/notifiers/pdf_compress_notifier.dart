import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pdf_service.dart';
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
      String sandboxPath;
      if (file.bytes != null) {
        sandboxPath = await _manager.writeToSandbox(file.bytes!, file.name);
      } else {
        sandboxPath = await _manager.copyToSandbox(file.path!);
      }

      state = state.copyWith(
        selectedFilePath: sandboxPath,
        selectedFileName: file.name,
        selectedFileSize: file.sizeBytes,
        errorMessage: null,
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

  /// Compresses the selected PDF file in a background isolate.
  /// The result stays in the sandbox until [exportFile] is called.
  Future<String?> compress() async {
    if (!state.hasFile) {
      state = state.copyWith(errorMessage: 'No file selected');
      return null;
    }

    state = state.copyWith(
      isProcessing: true,
      progress: 0.0,
      errorMessage: null,
      outputPath: null,
      outputFileSize: null,
      publicExportPath: null,
    );

    try {
      final inputBytes = File(state.selectedFilePath!).readAsBytesSync();
      state = state.copyWith(progress: 0.2);

      final appSettings = ref.read(appSettingsProvider);
      if (WatermarkHelper.cachedIconBytes == null) {
        await WatermarkHelper.loadIconBytes();
      }

      final resultBytes = await compute(
        PdfService.isolateCompressWorker,
        {
          'inputBytes': inputBytes,
          'quality': state.compressionLevel.qualityFactor,
          'applyWatermark': appSettings.enableGlobalWatermark,
          'watermarkText': appSettings.watermarkText,
          'watermarkPosition': appSettings.watermarkPosition,
          'watermarkOpacity': appSettings.watermarkOpacity,
          'watermarkColor': appSettings.watermarkColor,
          'useWatermarkLogo': appSettings.useWatermarkLogo,
          'iconBytes': WatermarkHelper.cachedIconBytes,
        },
      );

      state = state.copyWith(progress: 0.8);

      final saveDir =
          await ref.read(appSettingsProvider.notifier).getSaveDirectory();
      final selectedName = state.selectedFileName ?? 'compressed';
      final dot = selectedName.lastIndexOf('.');
      final baseName = dot > 0 ? selectedName.substring(0, dot) : selectedName;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'pixeltools_${baseName}_compressed_$timestamp.pdf';
      final outputPath = '${saveDir.path}/$fileName';
      final file = File(outputPath);
      await file.writeAsBytes(resultBytes, flush: true);

      final outputFileSize = await file.length();
      if (!await file.exists() || outputFileSize == 0) {
        throw Exception('Compressed PDF file was not created or is empty');
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPath: outputPath,
        outputFileSize: outputFileSize,
        publicExportPath: outputPath,
        errorMessage: !appSettings.enableGlobalWatermark &&
                outputFileSize >= (state.selectedFileSize ?? 0)
            ? 'This PDF is already highly optimized; no smaller output was possible.'
            : null,
      );

      return outputPath;
    } catch (e) {
      await _manager.cleanup();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Compression failed: $e',
      );
      return null;
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

  String _pdfBaseName(String? name) {
    final value = name ?? 'compressed';
    final dot = value.lastIndexOf('.');
    return dot > 0 ? value.substring(0, dot) : value;
  }
}
