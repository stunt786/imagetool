import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../shared/services/file_picker_service.dart';
import '../models/pdf_merge_state.dart';

final pdfMergeProvider = NotifierProvider<PdfMergeNotifier, PdfMergeState>(
  PdfMergeNotifier.new,
);

class PdfMergeNotifier extends Notifier<PdfMergeState> {
  final _manager = PrivateToPublicPdfManager();

  @override
  PdfMergeState build() => const PdfMergeState();

  /// Picks multiple PDF files and copies them into the sandbox cache.
  Future<void> pickFiles(BuildContext context) async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.pdfs,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final newFiles = <MergePdfItem>[];
    for (final file in picked) {
      try {
        String sandboxPath;
        if (file.bytes != null) {
          sandboxPath = await _manager.writeToSandbox(file.bytes!, file.name);
        } else if (file.path != null) {
          sandboxPath = await _manager.copyToSandbox(file.path!);
        } else {
          continue;
        }

        newFiles.add(MergePdfItem(
          path: sandboxPath,
          name: file.name,
          sizeBytes: file.sizeBytes,
        ));
      } catch (_) {
        continue;
      }
    }

    if (newFiles.isEmpty) {
      state = state.copyWith(errorMessage: 'Could not access the selected files');
      return;
    }

    state = state.copyWith(
      files: [...state.files, ...newFiles],
      errorMessage: null,
      outputPath: null,
      publicExportPath: null,
    );

    for (int i = state.files.length - newFiles.length; i < state.files.length; i++) {
      await _loadPageCount(i);
    }
  }

  /// Loads the page count for a file at the given index.
  Future<void> _loadPageCount(int index) async {
    if (index < 0 || index >= state.files.length) return;

    final item = state.files[index];
    if (item.pageCount != null) return;

    try {
      final pageCount = await PdfService.instance.getPageCount(item.path);
      final updatedItem = item.copyWith(pageCount: pageCount);
      state = state.updateFile(index, updatedItem);
    } catch (_) {}
  }

  /// Reorders files in the merge queue.
  void reorderFiles(int oldIndex, int newIndex) {
    state = state.reorderFiles(oldIndex, newIndex);
  }

  /// Removes a file from the merge queue.
  void removeFile(int index) {
    state = state.removeFile(index);
  }

  /// Merges all selected PDF files into one in a background isolate.
  /// The result stays in the sandbox until [exportFile] is called.
  Future<String?> merge() async {
    if (state.files.length < 2) {
      state = state.copyWith(errorMessage: 'At least 2 PDF files are required');
      return null;
    }

    state = state.copyWith(
      isProcessing: true,
      progress: 0.0,
      errorMessage: null,
      outputPath: null,
      publicExportPath: null,
    );

    try {
      state = state.copyWith(progress: 0.1);

      final filesData = state.files
          .map((f) => File(f.path).readAsBytesSync())
          .map((b) => Uint8List.fromList(b))
          .toList();

      state = state.copyWith(progress: 0.3);

      final resultBytes = await compute(
        PdfService.isolateMergeWorker,
        {'files': filesData},
      );

      state = state.copyWith(progress: 0.8);

      // Write result to sandbox (not public dir)
      final outputPath = await _manager.writeToSandbox(
        resultBytes,
        'merged.pdf',
      );

      if (!File(outputPath).existsSync()) {
        throw Exception('Merged PDF file was not created');
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPath: outputPath,
      );

      return outputPath;
    } catch (e) {
      await _manager.cleanup();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Merge failed: $e',
      );
      return null;
    }
  }

  /// Exports the merged file from the sandbox to a user-chosen public
  /// directory via SAF.
  Future<String?> exportFile() async {
    if (state.outputPath == null) return null;

    try {
      final resultPath = await _manager.exportSingleFile(
        sandboxPath: state.outputPath!,
        suggestedName: 'merged.pdf',
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

  /// Clears all files and results, cleaning the sandbox.
  void clear() {
    _manager.cleanup();
    state = state.reset();
  }

  /// Clears only the error message.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
