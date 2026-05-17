import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../../shared/services/file_picker_service.dart';
import '../models/pdf_convert_state.dart';

final pdfConvertProvider = NotifierProvider<PdfConvertNotifier, PdfConvertState>(
  PdfConvertNotifier.new,
);

class PdfConvertNotifier extends Notifier<PdfConvertState> {
  @override
  PdfConvertState build() => const PdfConvertState();

  /// Picks a single PDF file for conversion.
  Future<void> pickFile() async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
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
    final pageCount = await PdfService.instance.getPageCount(file.path!);

    state = state.copyWith(
      selectedFilePath: file.path,
      selectedFileName: file.name,
      selectedFileSize: fileSize,
      pageCount: pageCount,
      errorMessage: null,
      outputPaths: [],
    );
  }

  /// Sets the output format.
  void setOutputFormat(ConvertFormat format) {
    state = state.copyWith(outputFormat: format);
  }

  /// Sets the DPI for image conversion.
  void setDpi(ConvertDpi dpi) {
    state = state.copyWith(dpi: dpi);
  }

  /// Converts the selected PDF to the chosen format.
  Future<List<String>?> convert() async {
    if (!state.hasFile) {
      state = state.copyWith(errorMessage: 'No file selected');
      return null;
    }

    state = state.copyWith(
      isProcessing: true,
      progress: 0.0,
      errorMessage: null,
      outputPaths: [],
    );

    try {
      final baseName = state.selectedFileName!.replaceAll('.pdf', '');
      List<String> outputPaths;

      switch (state.outputFormat) {
        case ConvertFormat.jpg:
        case ConvertFormat.png:
          outputPaths = await PdfService.instance.convertPdfToImages(
            inputPath: state.selectedFilePath!,
            format: state.outputFormat.extension,
            outputBaseName: baseName,
            dpi: state.dpi.value,
            onProgress: (progress) {
              state = state.copyWith(progress: progress);
            },
          );
          break;

        case ConvertFormat.txt:
          final outputPath = await PdfService.instance.convertPdfToText(
            inputPath: state.selectedFilePath!,
            outputBaseName: baseName,
            onProgress: (progress) {
              state = state.copyWith(progress: progress);
            },
          );
          outputPaths = [outputPath];
          break;
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPaths: outputPaths,
      );

      return outputPaths;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Conversion failed: $e',
      );
      return null;
    }
  }

  /// Clears the current selection and results.
  void clear() {
    state = state.reset();
  }
}
