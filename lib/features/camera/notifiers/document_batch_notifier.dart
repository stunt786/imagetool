import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../models/document_batch.dart';
import '../models/scanned_page.dart';
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

  void startNewBatch() {
    state = DocumentBatch(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pages: [],
      createdAt: DateTime.now(),
    );
  }

  Future<void> addPageFromPath(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final name = path.basename(filePath);
    final sizeBytes = bytes.length;

    final page = ScannedPage(
      path: filePath,
      name: name,
      sizeBytes: sizeBytes,
      imageBytes: bytes,
      width: null,
      height: null,
    );

    state = state.addPage(page);
  }

  void removePage(int index) {
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

  void clearBatch() {
    state = const DocumentBatch(
      id: '',
      pages: [],
    );
  }

  String? get batchId => state.id.isEmpty ? null : state.id;
}
