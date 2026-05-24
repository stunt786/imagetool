import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../shared/services/file_picker_service.dart';
import '../models/pdf_split_state.dart';

final pdfSplitProvider = NotifierProvider<PdfSplitNotifier, PdfSplitState>(
  PdfSplitNotifier.new,
);

class PdfSplitNotifier extends Notifier<PdfSplitState> {
  final _manager = PrivateToPublicPdfManager();

  @override
  PdfSplitState build() => const PdfSplitState();

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

  /// Sets the split mode.
  void setSplitMode(SplitMode mode) {
    state = state.copyWith(splitMode: mode);
  }

  /// Sets the chunk size for by-chunks mode.
  void setChunkSize(int size) {
    if (size >= 1) {
      state = state.copyWith(chunkSize: size);
    }
  }

  /// Toggles a page selection.
  void togglePage(int pageNumber) {
    state = state.togglePage(pageNumber);
  }

  /// Selects all pages.
  void selectAllPages() {
    state = state.selectAllPages();
  }

  /// Clears page selection.
  void clearPageSelection() {
    state = state.clearPageSelection();
  }

  /// Executes the split operation based on the current mode in a background isolate.
  /// Results stay in the sandbox until [exportFiles] is called.
  Future<List<String>?> split() async {
    if (!state.hasFile || !state.hasPageInfo) {
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
      final inputBytes = File(state.selectedFilePath!).readAsBytesSync();
      state = state.copyWith(progress: 0.1);

      List<String> outputPaths;

      switch (state.splitMode) {
        case SplitMode.allPages:
          {
            final results = await compute(
              PdfService.isolateSplitAllPagesWorker,
              {'inputBytes': inputBytes},
            );
            state = state.copyWith(progress: 0.7);
            outputPaths = [];
            for (int i = 0; i < results.length; i++) {
              final sandboxPath = await _manager.writeToSandbox(
                results[i],
                '${baseName}_page_${i + 1}.pdf',
              );
              outputPaths.add(sandboxPath);
            }
          }
          break;

        case SplitMode.pageRange:
          {
            if (state.selectedPages.isEmpty) {
              state = state.copyWith(
                isProcessing: false,
                errorMessage: 'No pages selected',
              );
              return null;
            }
            final sortedPages = state.selectedPages.toList()..sort();
            final resultBytes = await compute(
              PdfService.isolateExtractPagesWorker,
              {
                'inputBytes': inputBytes,
                'pageNumbers': sortedPages,
              },
            );
            state = state.copyWith(progress: 0.7);
            final sandboxPath = await _manager.writeToSandbox(
              resultBytes,
              '${baseName}_extracted.pdf',
            );
            outputPaths = [sandboxPath];
          }
          break;

        case SplitMode.byChunks:
          {
            final results = await compute(
              PdfService.isolateSplitByChunksWorker,
              {
                'inputBytes': inputBytes,
                'pageSize': state.chunkSize,
              },
            );
            state = state.copyWith(progress: 0.7);
            outputPaths = [];
            for (int i = 0; i < results.length; i++) {
              final sandboxPath = await _manager.writeToSandbox(
                results[i],
                '${baseName}_part_${i + 1}.pdf',
              );
              outputPaths.add(sandboxPath);
            }
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
        errorMessage: 'Split failed: $e',
      );
      return null;
    }
  }

  /// Exports all split files from the sandbox to a user-chosen directory via SAF.
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
