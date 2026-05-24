import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../../shared/services/file_picker_service.dart';
import '../models/pdf_compress_state.dart';

final pdfCompressProvider = NotifierProvider<PdfCompressNotifier, PdfCompressState>(
  PdfCompressNotifier.new,
);

class PdfCompressNotifier extends Notifier<PdfCompressState> {
  @override
  PdfCompressState build() => const PdfCompressState();

  /// Picks a single PDF file for compression.
  Future<void> pickFile(BuildContext context) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.pdfs,
      allowMultiple: false,
    );

    if (picked.isEmpty) return;

    final file = picked.first;
    if (file.path == null) {
      state = state.copyWith(errorMessage: 'Could not access the selected file');
      return;
    }

    final fileSize = await File(file.path!).length();

    state = state.copyWith(
      selectedFilePath: file.path,
      selectedFileName: file.name,
      selectedFileSize: fileSize,
      errorMessage: null,
      outputPath: null,
      outputFileSize: null,
    );
  }

  /// Sets the compression level.
  void setCompressionLevel(CompressionLevel level) {
    state = state.copyWith(compressionLevel: level);
  }

  /// Compresses the selected PDF file.
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
    );

    try {
      final baseName = state.selectedFileName!.replaceAll('.pdf', '');
      final outputPath = await PdfService.instance.compressPdf(
        inputPath: state.selectedFilePath!,
        quality: state.compressionLevel.qualityFactor,
        outputBaseName: baseName,
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );

      final outputFileSize = await File(outputPath).length();

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPath: outputPath,
        outputFileSize: outputFileSize,
      );

      return outputPath;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Compression failed: $e',
      );
      return null;
    }
  }

  /// Clears the current selection and results.
  void clear() {
    state = state.reset();
  }

  /// Clears only the error message.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
