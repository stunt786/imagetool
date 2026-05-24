import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/pdf_service.dart';
import '../../../shared/services/file_picker_service.dart';
import '../models/pdf_compress_state.dart';

final pdfCompressProvider = NotifierProvider<PdfCompressNotifier, PdfCompressState>(
  PdfCompressNotifier.new,
);

class PdfCompressNotifier extends Notifier<PdfCompressState> {
  @override
  PdfCompressState build() => const PdfCompressState();

  /// Writes the picked file bytes to a permanent location in Downloads/PixelTools/.
  Future<String> _saveBytesPermanently(Uint8List bytes, String fileName) async {
    Directory baseDir;
    if (Platform.isAndroid) {
      try {
        final downloadDir = await getDownloadsDirectory();
        baseDir = (downloadDir != null)
            ? Directory(path.join(downloadDir.path, 'PixelTools'))
            : await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(path.join(baseDir.path, 'PDFs', 'picked'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final destPath = path.join(dir.path, 'source_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await File(destPath).writeAsBytes(bytes, flush: true);
    return destPath;
  }

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
    if (file.bytes == null) {
      state = state.copyWith(errorMessage: 'Could not read the selected file');
      return;
    }

    try {
      final permanentPath = await _saveBytesPermanently(file.bytes!, file.name);

      state = state.copyWith(
        selectedFilePath: permanentPath,
        selectedFileName: file.name,
        selectedFileSize: file.sizeBytes,
        errorMessage: null,
        outputPath: null,
        outputFileSize: null,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to access file: $e');
    }
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
