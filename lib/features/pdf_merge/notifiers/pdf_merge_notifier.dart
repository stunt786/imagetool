import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../../shared/services/file_picker_service.dart';
import '../models/pdf_merge_state.dart';

final pdfMergeProvider = NotifierProvider<PdfMergeNotifier, PdfMergeState>(
  PdfMergeNotifier.new,
);

class PdfMergeNotifier extends Notifier<PdfMergeState> {
  @override
  PdfMergeState build() => const PdfMergeState();

  /// Picks multiple PDF files for merging.
  Future<void> pickFiles() async {
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      target: PickTarget.pdfs,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final newFiles = <MergePdfItem>[];
    for (final file in picked) {
      if (file.path != null) {
        newFiles.add(MergePdfItem(
          path: file.path!,
          name: file.name,
          sizeBytes: file.sizeBytes,
        ));
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
    );

    // Load page counts for all new files
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
    } catch (_) {
      // Page count is optional, continue without it
    }
  }

  /// Reorders files in the merge queue.
  void reorderFiles(int oldIndex, int newIndex) {
    state = state.reorderFiles(oldIndex, newIndex);
  }

  /// Removes a file from the merge queue.
  void removeFile(int index) {
    state = state.removeFile(index);
  }

  /// Merges all selected PDF files into one.
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
    );

    try {
      final inputPaths = state.files.map((f) => f.path).toList();
      final outputPath = await PdfService.instance.mergePdfs(
        inputPaths: inputPaths,
        outputBaseName: 'merged',
        onProgress: (progress) {
          state = state.copyWith(progress: progress);
        },
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPath: outputPath,
      );

      return outputPath;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Merge failed: $e',
      );
      return null;
    }
  }

  /// Clears all files and results.
  void clear() {
    state = state.reset();
  }
}
