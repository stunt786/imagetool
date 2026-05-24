import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/services/pdf_service.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../shared/services/file_picker_service.dart';
import '../models/pdf_convert_state.dart';

final pdfConvertProvider = NotifierProvider<PdfConvertNotifier, PdfConvertState>(
  PdfConvertNotifier.new,
);

class PdfConvertNotifier extends Notifier<PdfConvertState> {
  final _manager = PrivateToPublicPdfManager();

  @override
  PdfConvertState build() => const PdfConvertState();

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
    if (file.path == null && file.bytes == null) {
      state = state.copyWith(errorMessage: 'Could not access the selected file');
      return;
    }

    try {
      String sandboxPath;
      if (file.bytes != null) {
        sandboxPath = await _manager.writeToSandbox(file.bytes!, file.name);
      } else {
        sandboxPath = await _manager.copyToSandbox(file.path!);
      }

      final fileSize = File(sandboxPath).lengthSync();
      final pageCount = await PdfService.instance.getPageCount(sandboxPath);

      state = state.copyWith(
        selectedFilePath: sandboxPath,
        selectedFileName: file.name,
        selectedFileSize: fileSize,
        pageCount: pageCount,
        errorMessage: null,
        outputPaths: [],
        publicExportPaths: [],
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to access file: $e');
    }
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
  /// Results stay in the sandbox until [exportFiles] is called.
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
      publicExportPaths: [],
    );

    try {
      final baseName = state.selectedFileName!.replaceAll('.pdf', '');
      List<String> outputPaths;

      switch (state.outputFormat) {
        case ConvertFormat.jpg:
        case ConvertFormat.png:
          final pdfDoc = await pdfx.PdfDocument.openFile(
            state.selectedFilePath!,
          );
          final pageCount = pdfDoc.pagesCount;
          final scale = state.dpi.value / 72.0;
          final renderedPages = <Uint8List>[];
          state = state.copyWith(progress: 0.1);

          for (int i = 1; i <= pageCount; i++) {
            final page = await pdfDoc.getPage(i);
            final pageImage = await page.render(
              width: page.width * scale,
              height: page.height * scale,
              format: pdfx.PdfPageImageFormat.png,
            );
            if (pageImage != null) {
              renderedPages.add(pageImage.bytes);
            }
            await page.close();
            state = state.copyWith(progress: 0.1 + (i / pageCount) * 0.4);
          }
          await pdfDoc.close();

          state = state.copyWith(progress: 0.6);

          final encodedResults = await compute(
            PdfService.isolateEncodeImagesWorker,
            {
              'renderedPages': renderedPages,
              'format': state.outputFormat.extension,
            },
          );

          state = state.copyWith(progress: 0.9);

          outputPaths = [];
          for (int i = 0; i < encodedResults.length; i++) {
            final ext = state.outputFormat.extension;
            final fileName = '${baseName}_page_${i + 1}.$ext';
            final sandboxPath = await _manager.writeToSandbox(
              encodedResults[i],
              fileName,
            );
            outputPaths.add(sandboxPath);
          }
          break;

        case ConvertFormat.txt:
          {
            final srcPath = await PdfService.instance.convertPdfToText(
              inputPath: state.selectedFilePath!,
              outputBaseName: baseName,
              onProgress: (progress) {
                state = state.copyWith(progress: progress);
              },
            );
            final sandboxPath = await _manager.copyToSandbox(srcPath);
            // Remove the file written to saveDir; sandbox is now the source
            try { await File(srcPath).delete(); } catch (_) {}
            outputPaths = [sandboxPath];
          }
          break;

        case ConvertFormat.docx:
          {
            final srcPath = await PdfService.instance.convertPdfToDocx(
              inputPath: state.selectedFilePath!,
              outputBaseName: baseName,
              onProgress: (progress) {
                state = state.copyWith(progress: progress);
              },
            );
            final sandboxPath = await _manager.copyToSandbox(srcPath);
            try { await File(srcPath).delete(); } catch (_) {}
            outputPaths = [sandboxPath];
          }
          break;
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPaths: outputPaths,
      );

      return outputPaths;
    } catch (e) {
      await _manager.cleanup();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Conversion failed: $e',
      );
      return null;
    }
  }

  /// Exports all converted files from the sandbox to a user-chosen directory
  /// via SAF.
  Future<List<String>?> exportFiles() async {
    if (state.outputPaths.isEmpty) return null;

    try {
      final resultPaths = await _manager.exportMultipleFiles(
        sandboxPaths: state.outputPaths,
        nameOverride: (i, sandboxPath) => sandboxPath.split('/').last,
      );

      if (resultPaths.isNotEmpty) {
        state = state.copyWith(publicExportPaths: resultPaths);
      }

      return resultPaths;
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
}
