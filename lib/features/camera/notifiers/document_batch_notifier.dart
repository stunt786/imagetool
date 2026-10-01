import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/settings/app_settings.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/services/watermark_helper.dart';
import '../models/document_batch.dart';
import '../models/scanned_page.dart';
import '../services/batch_storage_service.dart';
import '../services/image_filter_service.dart';

final documentBatchProvider =
    NotifierProvider<DocumentBatchNotifier, DocumentBatch>(
  DocumentBatchNotifier.new,
);

class DocumentBatchNotifier extends Notifier<DocumentBatch> {
  final List<DocumentBatch> _undoStack = <DocumentBatch>[];
  final List<DocumentBatch> _redoStack = <DocumentBatch>[];
  static const int _maxUndoSteps = 20;

  @override
  DocumentBatch build() {
    return const DocumentBatch(
      id: '',
      pages: [],
    );
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _syncUndoDepths() {
    state = state.copyWith(
      undoDepth: _undoStack.length,
      redoDepth: _redoStack.length,
    );
  }

  void _recordEdit() {
    if (!state.hasPages) return;
    _undoStack.add(state);
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(state);
    state = _undoStack.removeLast();
    _syncUndoDepths();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(state);
    state = _redoStack.removeLast();
    _syncUndoDepths();
  }

  /// Returns the display bytes of a scanned page, applying global watermark if enabled.
  Uint8List getExportPageBytes(int index, AppSettingsState settings) {
    final page = state.pages.elementAtOrNull(index);
    if (page == null) return Uint8List(0);
    return WatermarkHelper.applyGlobalWatermarkIfNeeded(
        page.displayBytes, settings);
  }

  /// Returns all scanned page bytes for export, applying global watermark if enabled.
  List<Uint8List> getAllExportPageBytes(AppSettingsState settings) {
    return state.pages
        .map((page) => WatermarkHelper.applyGlobalWatermarkIfNeeded(
              page.displayBytes,
              settings,
            ))
        .toList();
  }

  Future<void> startNewBatch() async {
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final batchDir = await BatchStorageService.createBatchDirectory(batchId);

    state = DocumentBatch(
      id: batchId,
      pages: [],
      createdAt: DateTime.now(),
      batchDirectory: batchDir.path,
    );
    _undoStack.clear();
    _redoStack.clear();
    _syncUndoDepths();
  }

  Future<void> addPageFromPath(String filePath, {bool skipExifFix = false}) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    var bytes = await file.readAsBytes();
    final name = p.basename(filePath);
    final sizeBytes = bytes.length;

    // Fix EXIF orientation off the UI isolate if needed (skip for scanner outputs)
    if (!skipExifFix) {
      try {
        bytes = await compute(_fixOrientationWorker, bytes);
      } catch (_) {
        // If decode fails, use original bytes
      }
    }

    var savedPath = filePath;
    if (state.id.isNotEmpty && state.batchDirectory != null) {
      final pageIndex = state.pages.length;
      savedPath = await BatchStorageService.savePage(
        batchId: state.id,
        pageIndex: pageIndex,
        imageBytes: bytes,
      );
    }

    final page = ScannedPage(
      path: savedPath,
      name: name,
      sizeBytes: sizeBytes,
      imageBytes: bytes,
      width: null,
      height: null,
    );

    _recordEdit();
    state = state.addPage(page);
    _syncUndoDepths();
  }

  void addPage(ScannedPage page) {
    _recordEdit();
    state = state.addPage(page);
    _syncUndoDepths();
  }

  Future<void> removePage(int index) async {
    final page = state.pages.elementAtOrNull(index);
    if (page != null && page.path.isNotEmpty) {
      await BatchStorageService.deletePageFile(page.path);
    }
    _recordEdit();
    state = state.removePage(index);
    _syncUndoDepths();
  }

  Future<void> replacePageFromPath(int index, String filePath, {bool skipExifFix = false}) async {
    final oldPage = state.pages.elementAtOrNull(index);
    if (oldPage != null && oldPage.path.isNotEmpty) {
      await BatchStorageService.deletePageFile(oldPage.path);
    }

    final file = File(filePath);
    if (!await file.exists()) return;

    var bytes = await file.readAsBytes();
    final name = p.basename(filePath);
    final sizeBytes = bytes.length;

    // Fix EXIF orientation off the UI isolate if needed (skip for scanner outputs)
    if (!skipExifFix) {
      try {
        bytes = await compute(_fixOrientationWorker, bytes);
      } catch (_) {
        // If decode fails, use original bytes
      }
    }

    var savedPath = filePath;
    if (state.id.isNotEmpty && state.batchDirectory != null) {
      savedPath = await BatchStorageService.savePage(
        batchId: state.id,
        pageIndex: index,
        imageBytes: bytes,
      );
    }

    final page = ScannedPage(
      path: savedPath,
      name: name,
      sizeBytes: sizeBytes,
      imageBytes: bytes,
      width: null,
      height: null,
    );

    _recordEdit();
    state = state.updatePage(index, page);
    _syncUndoDepths();
  }

  void reorderPages(int oldIndex, int newIndex) {
    _recordEdit();
    state = state.reorderPages(oldIndex, newIndex);
    _syncUndoDepths();
  }

  void updatePage(int index, ScannedPage page) {
    _recordEdit();
    state = state.updatePage(index, page);
    _syncUndoDepths();
  }

  /// Updates the in-memory page and persists the edited image in the batch
  /// directory so crop/rotation edits survive leaving the editor.
  Future<void> updatePageAndPersist(int index, ScannedPage page) async {
    if (index < 0 || index >= state.pages.length) return;

    _recordEdit();
    var persistedPage = page;
    if (state.id.isNotEmpty &&
        state.batchDirectory != null &&
        page.displayBytes.isNotEmpty) {
      final savedPath = await BatchStorageService.savePage(
        batchId: state.id,
        pageIndex: index,
        // Keep filters non-destructive in the editing state, while writing
        // exactly the visible edited page for Files/later export.
        imageBytes: page.displayBytes,
      );
      persistedPage = page.copyWith(path: savedPath);
    }
    state = state.updatePage(index, persistedPage);
    _syncUndoDepths();
  }

  Future<void> applyFilterToPage(int index, FilterType filterType) async {
    final page = state.pages.elementAtOrNull(index);
    if (page == null || !page.isLoaded) return;

    Uint8List originalBytes = page.imageBytes!;

    if (filterType == FilterType.none) {
      await updatePageAndPersist(index, page.copyWith(clearFilter: true));
      return;
    }

    try {
      final ImageFilterResult? result =
          await ImageFilterService.applyFilter(originalBytes, filterType);

      if (result != null) {
        await updatePageAndPersist(
          index,
          page.copyWith(
            filteredBytes: result.bytes,
            filterType: filterType,
            width: result.width,
            height: result.height,
          ),
        );
        _saveToEditHistory(filterType: filterType);
      }
    } catch (e) {
      // Filter failed, keep original
    }
  }

  Future<void> applyFilterToAllPages(FilterType filterType) async {
    for (var i = 0; i < state.pages.length; i++) {
      await applyFilterToPage(i, filterType);
    }
  }

  Future<void> clearBatch() async {
    if (state.id.isNotEmpty) {
      await BatchStorageService.deleteBatch(state.id);
    }
    state = const DocumentBatch(
      id: '',
      pages: [],
    );
    _undoStack.clear();
    _redoStack.clear();
  }

  void _saveToEditHistory({FilterType? filterType}) {
    if (state.pages.isEmpty) return;
    final firstPage = state.pages.first;
    final filePath = firstPage.path.isNotEmpty ? firstPage.path : null;

    final toolName = filterType != null
        ? 'Scan (${_filterDisplayName(filterType)})'
        : 'Document Scan';

    ref.read(editHistoryProvider.notifier).addGroup(
          toolName: toolName,
          toolIcon: Icons.document_scanner_outlined,
          count: state.pages.length,
          filePath: filePath,
        );
  }

  String _filterDisplayName(FilterType type) {
    switch (type) {
      case FilterType.magicColor:
        return 'Magic Color';
      case FilterType.binarization:
        return 'Binarize';
      case FilterType.shadowRemoval:
        return 'No Shadow';
      case FilterType.lighten:
        return 'Lighten';
      case FilterType.enhance:
        return 'Enhance';
      case FilterType.noShadow:
        return 'No Shadow';
      case FilterType.blackWhite:
        return 'B&W';
      case FilterType.eco:
        return 'Eco';
      case FilterType.grayscale:
        return 'Grayscale';
      case FilterType.invert:
        return 'Invert';
      case FilterType.sepia:
        return 'Sepia';
      case FilterType.warm:
        return 'Warm';
      case FilterType.cool:
        return 'Cool';
      case FilterType.dramatic:
        return 'Dramatic';
      case FilterType.bwHighContrast:
        return 'B&W High Contrast';
      case FilterType.autoFlatten:
        return 'Auto Flatten';
      case FilterType.antiLight:
        return 'Anti-Light Shadow';
      case FilterType.autoBrighten:
        return 'Auto Brighten';
      case FilterType.smartScan:
        return 'Smart Clean';
      case FilterType.none:
        return 'Original';
    }
  }

  String? get batchId => state.id.isEmpty ? null : state.id;
}

Uint8List _fixOrientationWorker(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
    }
  } catch (_) {}
  return bytes;
}
