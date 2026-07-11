import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/document_batch.dart';
import '../models/scanned_page.dart';
import '../services/batch_storage_service.dart';
import '../services/image_filter_service.dart';

final documentBatchProvider =
    NotifierProvider<DocumentBatchNotifier, DocumentBatch>(
  DocumentBatchNotifier.new,
);

class DocumentBatchNotifier extends Notifier<DocumentBatch> {
  @override
  DocumentBatch build() {
    return const DocumentBatch(
      id: '',
      pages: [],
    );
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
  }

  Future<void> addPageFromPath(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final name = p.basename(filePath);
    final sizeBytes = bytes.length;

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

    state = state.addPage(page);
  }

  Future<void> removePage(int index) async {
    final page = state.pages.elementAtOrNull(index);
    if (page != null && page.path.isNotEmpty) {
      await BatchStorageService.deletePageFile(page.path);
    }
    state = state.removePage(index);
  }

  void reorderPages(int oldIndex, int newIndex) {
    state = state.reorderPages(oldIndex, newIndex);
  }

  void updatePage(int index, ScannedPage page) {
    state = state.updatePage(index, page);
  }

  Future<void> applyFilterToPage(int index, FilterType filterType) async {
    final page = state.pages.elementAtOrNull(index);
    if (page == null || !page.isLoaded) return;

    Uint8List originalBytes = page.imageBytes!;

    if (filterType == FilterType.none) {
      state = state.updatePage(
        index,
        page.copyWith(clearFilter: true),
      );
      return;
    }

    try {
      ImageFilterResult? result;
      switch (filterType) {
        case FilterType.magicColor:
          result = await ImageFilterService.applyMagicColor(originalBytes);
        case FilterType.binarization:
          result = await ImageFilterService.applyBinarization(originalBytes);
        case FilterType.shadowRemoval:
          result = await ImageFilterService.applyShadowRemoval(originalBytes);
        case FilterType.none:
          break;
      }

      if (result != null) {
        state = state.updatePage(
          index,
          page.copyWith(
            filteredBytes: result.bytes,
            filterType: filterType,
            width: result.width,
            height: result.height,
          ),
        );
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
  }

  String? get batchId => state.id.isEmpty ? null : state.id;
}
