import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/services/pdf_service.dart';
import '../../../core/models/operation_folder.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/utils/file_type_detector.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/pdf_convert_state.dart';

final pdfConvertProvider =
    NotifierProvider<PdfConvertNotifier, PdfConvertState>(
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
      state =
          state.copyWith(errorMessage: 'Could not access the selected file');
      return;
    }

    final fileSize = file.sizeBytes > 0
        ? file.sizeBytes
        : (file.path != null
            ? File(file.path!).lengthSync()
            : (file.bytes?.length ?? 0));
    if (fileSize > FileTypeDetector.maxPdfSizeBytes) {
      state = state.copyWith(
        errorMessage: 'Selected PDF exceeds the 20 MB size limit.',
      );
      return;
    }

    if (file.bytes != null && !FileTypeDetector.looksLikePdf(file.bytes!)) {
      state = state.copyWith(errorMessage: 'Selected file is not a valid PDF.');
      return;
    }

    try {
      final sandboxPath = await _manager.importPickedFile(file);

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

  void setPagesToConvert(int? pages) {
    state = pages == null
        ? state.copyWith(clearPagesToConvert: true)
        : state.copyWith(pagesToConvert: pages);
  }

  void setPageRange(int? start, int? end) {
    if (start == null || end == null) {
      state = state.copyWith(clearPageRange: true);
    } else {
      state = state.copyWith(pageRangeStart: start, pageRangeEnd: end);
    }
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
      final selectedName = state.selectedFileName!;
      final dot = selectedName.lastIndexOf('.');
      final rawBase = dot > 0 ? selectedName.substring(0, dot) : selectedName;
      final baseName =
          path.basename(rawBase).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');
      final saveDir =
          await ref.read(appSettingsProvider.notifier).getSaveDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      List<OutputEntry> entries;

      switch (state.outputFormat) {
        case ConvertFormat.jpg:
        case ConvertFormat.png:
          final pdfDoc = await pdfx.PdfDocument.openFile(
            state.selectedFilePath!,
          );
          final startPage = state.usePageRange
              ? state.pageRangeStart!.clamp(1, pdfDoc.pagesCount)
              : 1;
          final endPage = state.usePageRange
              ? state.pageRangeEnd!.clamp(startPage, pdfDoc.pagesCount)
              : pdfDoc.pagesCount;
          final pageCount = endPage - startPage + 1;
          final scale = state.dpi.value / 72.0;
          final renderedPages = <Uint8List>[];
          state = state.copyWith(progress: 0.1);

          for (int i = startPage; i <= endPage; i++) {
            final page = await pdfDoc.getPage(i);
            final pageImage = await page.render(
              width: page.width * scale,
              height: page.height * scale,
              format: pdfx.PdfPageImageFormat.png,
              backgroundColor: '#FFFFFF',
            );
            if (pageImage != null) {
              renderedPages.add(pageImage.bytes);
            }
            await page.close();
            state = state.copyWith(
                progress: 0.1 + ((i - startPage + 1) / pageCount) * 0.4);
          }
          await pdfDoc.close();

          state = state.copyWith(progress: 0.6);

          final appSettings = ref.read(appSettingsProvider);
          final watermarkApplied = <Uint8List>[];
          for (final pageBytes in renderedPages) {
            watermarkApplied.add(
              WatermarkHelper.applyGlobalWatermarkIfNeeded(
                  pageBytes, appSettings),
            );
          }

          final encodedResults = await compute(
            PdfService.isolateEncodeImagesWorker,
            {
              'renderedPages': watermarkApplied,
              'format': state.outputFormat.extension,
            },
          );

          state = state.copyWith(progress: 0.9);

          entries = [];
          for (int i = 0; i < encodedResults.length; i++) {
            final ext = state.outputFormat.extension;
            final fileName =
                'pixeltools_${baseName}_${timestamp}_page_${startPage + i}.$ext';
            entries.add(OutputEntry.bytes(
              bytes: encodedResults[i],
              fileName: fileName,
              publicKind: PublicFileKind.image,
            ));
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
            entries = [
              OutputEntry.file(
                sourcePath: srcPath,
                fileName: 'pixeltools_${baseName}_$timestamp.txt',
              ),
            ];
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
            entries = [
              OutputEntry.file(
                sourcePath: srcPath,
                fileName: 'pixeltools_${baseName}_$timestamp.docx',
              ),
            ];
          }
          break;
      }

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.pdfConvert,
        entries: entries,
        stagingDirectory: saveDir,
      );
      final outputPaths = [for (final result in saved) result.localPath];
      final publicPaths = [
        for (final result in saved)
          if (result.publicPath != null) result.publicPath!,
      ];

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPaths: outputPaths,
        publicExportPaths: publicPaths,
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
