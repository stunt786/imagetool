import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/settings/app_settings.dart';
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
  @override
  DocumentBatch build() {
    return const DocumentBatch(
      id: '',
      pages: [],
    );
  }

  /// Returns the display bytes of a scanned page, applying global watermark if enabled.
  Uint8List getExportPageBytes(int index, AppSettingsState settings) {
    final page = state.pages.elementAtOrNull(index);
    if (page == null) return Uint8List(0);
    return WatermarkHelper.applyGlobalWatermarkIfNeeded(page.displayBytes, settings);
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
  }

  Future<void> addPageFromPath(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    var bytes = await file.readAsBytes();
    final name = p.basename(filePath);
    final sizeBytes = bytes.length;

    // Fix EXIF orientation by decoding and re-encoding
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        // Re-encode as JPEG with proper orientation (EXIF stripped)
        bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
      }
    } catch (_) {
      // If decode fails, use original bytes
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

    state = state.addPage(page);
    
    // Auto-apply shadow removal for cleaner scan output
    final newIndex = state.pages.length - 1;
    _autoApplyShadowRemoval(newIndex);
  }

  Future<void> removePage(int index) async {
    final page = state.pages.elementAtOrNull(index);
    if (page != null && page.path.isNotEmpty) {
      await BatchStorageService.deletePageFile(page.path);
    }
    state = state.removePage(index);
  }

  Future<void> replacePageFromPath(int index, String filePath) async {
    final oldPage = state.pages.elementAtOrNull(index);
    if (oldPage != null && oldPage.path.isNotEmpty) {
      await BatchStorageService.deletePageFile(oldPage.path);
    }

    final file = File(filePath);
    if (!await file.exists()) return;

    var bytes = await file.readAsBytes();
    final name = p.basename(filePath);
    final sizeBytes = bytes.length;

    // Fix EXIF orientation by decoding and re-encoding
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        // Re-encode as JPEG with proper orientation (EXIF stripped)
        bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
      }
    } catch (_) {
      // If decode fails, use original bytes
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

    state = state.updatePage(index, page);
  }

  void reorderPages(int oldIndex, int newIndex) {
    state = state.reorderPages(oldIndex, newIndex);
  }

  void updatePage(int index, ScannedPage page) {
    state = state.updatePage(index, page);
  }

  /// Updates the in-memory page and persists the edited image in the batch
  /// directory so crop/rotation edits survive leaving the editor.
  Future<void> updatePageAndPersist(int index, ScannedPage page) async {
    if (index < 0 || index >= state.pages.length) return;

    var persistedPage = page;
    if (state.id.isNotEmpty &&
        state.batchDirectory != null &&
        page.imageBytes != null) {
      final savedPath = await BatchStorageService.savePage(
        batchId: state.id,
        pageIndex: index,
        imageBytes: page.imageBytes!,
      );
      persistedPage = page.copyWith(path: savedPath);
    }
    state = state.updatePage(index, persistedPage);
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
      final ImageFilterResult? result =
          await ImageFilterService.applyFilter(originalBytes, filterType);

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

  /// Silently applies shadow removal filter to the given page index.
  Future<void> _autoApplyShadowRemoval(int index) async {
    try {
      await applyFilterToPage(index, FilterType.shadowRemoval);
    } catch (_) {
      // Shadow removal is best-effort; failure is silent.
    }
  }

  String? get batchId => state.id.isEmpty ? null : state.id;
}
