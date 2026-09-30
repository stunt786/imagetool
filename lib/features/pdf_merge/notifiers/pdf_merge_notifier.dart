import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/models/operation_folder.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/services/file_picker_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/pdf_merge_state.dart';

import '../../../core/utils/file_type_detector.dart';

final pdfMergeProvider = NotifierProvider<PdfMergeNotifier, PdfMergeState>(
  PdfMergeNotifier.new,
);

class PdfMergeNotifier extends Notifier<PdfMergeState> {
  final _manager = PrivateToPublicPdfManager();

  @override
  PdfMergeState build() => const PdfMergeState();

  /// Picks multiple PDF files and copies them into the sandbox cache.
  Future<void> pickFiles(BuildContext context) async {
    const maxCount = FileTypeDetector.maxMergePdfCount;
    final currentCount = state.files.length;
    if (currentCount >= maxCount) {
      state = state.copyWith(
        errorMessage: 'Only up to $maxCount PDFs can be merged at a time.',
      );
      return;
    }

    final remaining = maxCount - currentCount;
    final service = ref.read(filePickerServiceProvider);
    final picked = await service.pick(
      context: context,
      target: PickTarget.pdfs,
      allowMultiple: true,
    );

    if (picked.isEmpty) return;

    final newFiles = <MergePdfItem>[];
    var sizeExceededCount = 0;
    var duplicateCount = 0;
    var countCapped = false;

    for (final file in picked) {
      if (file.sizeBytes > FileTypeDetector.maxPdfSizeBytes) {
        sizeExceededCount++;
        continue;
      }

      final isDuplicate = state.files.any((f) =>
              f.name == file.name &&
              (f.sizeBytes == file.sizeBytes || f.path == file.path)) ||
          newFiles.any((f) =>
              f.name == file.name && f.sizeBytes == file.sizeBytes);
      if (isDuplicate) {
        duplicateCount++;
        continue;
      }

      if (newFiles.length >= remaining) {
        countCapped = true;
        break;
      }

      try {
        final sandboxPath = await _manager.importPickedFile(file);

        newFiles.add(MergePdfItem(
          path: sandboxPath,
          name: file.name,
          sizeBytes: file.sizeBytes,
        ));
      } catch (_) {
        continue;
      }
    }

    var pagesExceeded = false;
    final validFilesToAdd = <MergePdfItem>[];
    var currentTotalPages =
        state.files.fold<int>(0, (sum, f) => sum + (f.pageCount ?? 0));

    for (final item in newFiles) {
      int? pageCount;
      try {
        pageCount = await PdfService.instance.getPageCount(item.path);
      } catch (_) {}

      final pages = pageCount ?? 0;
      if (currentTotalPages + pages > FileTypeDetector.maxMergeCombinedPages) {
        pagesExceeded = true;
        try {
          await File(item.path).delete();
        } catch (_) {}
        continue;
      }

      currentTotalPages += pages;
      validFilesToAdd.add(item.copyWith(pageCount: pageCount));
    }

    final notices = <String>[];
    if (duplicateCount > 0) {
      notices.add(
        duplicateCount == 1
            ? '1 duplicate PDF was skipped.'
            : '$duplicateCount duplicate PDFs were skipped.',
      );
    }
    if (sizeExceededCount > 0) {
      notices.add(
        sizeExceededCount == 1
            ? '1 PDF exceeded the 20 MB size limit and was skipped.'
            : '$sizeExceededCount PDFs exceeded the 20 MB size limit and were skipped.',
      );
    }
    if (pagesExceeded) {
      notices.add(
        'Some files could not be added because combined pages cannot exceed ${FileTypeDetector.maxMergeCombinedPages} pages.',
      );
    }
    if (countCapped) {
      notices.add('Only up to $maxCount PDFs can be merged at a time.');
    }

    final noticeMsg = notices.isNotEmpty ? notices.join(' ') : null;

    if (validFilesToAdd.isEmpty) {
      state = state.copyWith(
        errorMessage: noticeMsg ?? 'Could not access the selected files.',
      );
      return;
    }

    state = state.copyWith(
      files: [...state.files, ...validFilesToAdd],
      errorMessage: noticeMsg,
      outputPath: null,
      publicExportPath: null,
    );
  }

  /// Loads the page count for a file at the given index.
  Future<void> loadPageCount(int index) async {
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
      state = state.copyWith(errorMessage: 'At least 2 PDF files are required to merge.');
      return null;
    }

    if (state.files.length > FileTypeDetector.maxMergePdfCount) {
      state = state.copyWith(
        errorMessage: 'Only up to ${FileTypeDetector.maxMergePdfCount} PDFs can be merged at a time.',
      );
      return null;
    }

    for (final file in state.files) {
      if (file.sizeBytes > FileTypeDetector.maxPdfSizeBytes) {
        state = state.copyWith(
          errorMessage: 'File "${file.name}" exceeds the 20 MB size limit.',
        );
        return null;
      }
    }

    final totalPages =
        state.files.fold<int>(0, (sum, f) => sum + (f.pageCount ?? 0));
    if (totalPages > FileTypeDetector.maxMergeCombinedPages) {
      state = state.copyWith(
        errorMessage:
            'Combined page count ($totalPages) exceeds the limit of ${FileTypeDetector.maxMergeCombinedPages} pages.',
      );
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

      final filePaths = state.files.map((f) => f.path).toList();

      state = state.copyWith(progress: 0.3);

      final appSettings = ref.read(appSettingsProvider);
      if (WatermarkHelper.cachedIconBytes == null) {
        await WatermarkHelper.loadIconBytes();
      }

      final resultBytes = await compute(
        PdfService.isolateMergeWorker,
        {
          'filePaths': filePaths,
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
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final firstName = state.files.first.name;
      final dot = firstName.lastIndexOf('.');
      final baseName = dot > 0 ? firstName.substring(0, dot) : firstName;
      final fileName = 'pixeltools_${baseName}_merged_$timestamp.pdf';

      if (resultBytes.isEmpty) {
        throw Exception('Merged PDF file was not created or is empty');
      }

      // One grouped copy in Files, plus the public save (MediaStore or the
      // SAF folder chosen in Settings).
      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.pdfMerge,
        entries: [
          OutputEntry.bytes(bytes: resultBytes, fileName: fileName),
        ],
        stagingDirectory: saveDir,
      );
      final outputPath = saved.first.localPath;

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        outputPath: outputPath,
        publicExportPath: saved.first.publicPath,
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
        suggestedName:
            'pixeltools_${_pdfBaseName(state.files.first.name)}_merged.pdf',
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

  String _pdfBaseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
