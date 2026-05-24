import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../../shared/services/file_picker_service.dart';
import '../models/pdf_split_state.dart';

final pdfSplitProvider = NotifierProvider<PdfSplitNotifier, PdfSplitState>(
  PdfSplitNotifier.new,
);

class PdfSplitNotifier extends Notifier<PdfSplitState> {
  @override
  PdfSplitState build() => const PdfSplitState();

  /// Picks a single PDF file for splitting.
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

  /// Executes the split operation based on the current mode.
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
    );

    try {
      final baseName = state.selectedFileName!.replaceAll('.pdf', '');
      List<String> outputPaths;

      switch (state.splitMode) {
        case SplitMode.allPages:
          outputPaths = await PdfService.instance.splitPdfAllPages(
            inputPath: state.selectedFilePath!,
            outputBaseName: baseName,
            onProgress: (progress) {
              state = state.copyWith(progress: progress);
            },
          );
          break;

        case SplitMode.pageRange:
          if (state.selectedPages.isEmpty) {
            state = state.copyWith(
              isProcessing: false,
              errorMessage: 'No pages selected',
            );
            return null;
          }
          final sortedPages = state.selectedPages.toList()..sort();
          final outputPath = await PdfService.instance.extractPages(
            inputPath: state.selectedFilePath!,
            pageNumbers: sortedPages,
            outputBaseName: baseName,
            onProgress: (progress) {
              state = state.copyWith(progress: progress);
            },
          );
          outputPaths = [outputPath];
          break;

        case SplitMode.byChunks:
          outputPaths = await PdfService.instance.splitPdfByChunk(
            inputPath: state.selectedFilePath!,
            pageSize: state.chunkSize,
            outputBaseName: baseName,
            onProgress: (progress) {
              state = state.copyWith(progress: progress);
            },
          );
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
        errorMessage: 'Split failed: $e',
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
