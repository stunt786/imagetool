import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/camera/models/document_batch.dart';
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/notifiers/document_batch_notifier.dart';
import 'package:pixeltools/features/camera/services/image_filter_service.dart';
import 'package:pixeltools/shared/notifiers/edit_history_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempRoot, this.docsRoot);

  final String tempRoot;
  final String docsRoot;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsRoot;

  @override
  Future<String?> getTemporaryPath() async => tempRoot;
}

Uint8List _jpg(int width, int height, {int gray = 200}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, gray, gray, gray, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

ScannedPage _page(String name, {Uint8List? bytes, String path = ''}) {
  final payload = bytes ?? _jpg(40, 40);
  return ScannedPage(
    path: path,
    name: name,
    sizeBytes: payload.length,
    imageBytes: payload,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory docsRoot;
  late PathProviderPlatform initialPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempRoot = await Directory.systemTemp.createTemp('camera_batch_temp_');
    docsRoot = await Directory.systemTemp.createTemp('camera_batch_docs_');
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path, docsRoot.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    for (final dir in [tempRoot, docsRoot]) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  });

  ProviderContainer newContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  const offWatermark = AppSettingsState(savePath: '', enableGlobalWatermark: false);

  group('DocumentBatch model', () {
    test('starts empty with zero counts', () {
      const batch = DocumentBatch(id: 'b', pages: []);
      expect(batch.pageCount, 0);
      expect(batch.hasPages, isFalse);
    });

    test('addPage appends and leaves the source batch untouched', () {
      const batch = DocumentBatch(id: 'b', pages: []);
      final one = batch.addPage(_page('a.jpg'));
      final two = one.addPage(_page('b.jpg'));

      expect(batch.pageCount, 0);
      expect(one.pageCount, 1);
      expect(two.pageCount, 2);
      expect(two.pages.last.name, 'b.jpg');
      expect(two.hasPages, isTrue);
    });

    test('removePage drops the entry and rejects out of range indexes', () {
      var batch = const DocumentBatch(id: 'b', pages: []);
      batch = batch.addPage(_page('a.jpg')).addPage(_page('b.jpg'));

      expect(batch.removePage(-1), same(batch));
      expect(batch.removePage(5), same(batch));
      expect(batch.pageCount, 2);

      final removed = batch.removePage(0);
      expect(removed.pageCount, 1);
      expect(removed.pages.single.name, 'b.jpg');
      expect(batch.pageCount, 2, reason: 'original must not be mutated');
    });

    test('reorderPages moves items in both directions', () {
      var batch = const DocumentBatch(id: 'b', pages: []);
      batch = batch
          .addPage(_page('a.jpg'))
          .addPage(_page('b.jpg'))
          .addPage(_page('c.jpg'));

      expect(batch.reorderPages(1, 1), same(batch),
          reason: 'no-op reorder returns the same instance');

      // Follows the ReorderableListView convention: a move down is reported
      // as "insert at newIndex", which the model adjusts by one.
      final movedDown = batch.reorderPages(0, 2);
      expect(
        movedDown.pages.map((p) => p.name).toList(),
        ['b.jpg', 'a.jpg', 'c.jpg'],
      );

      final movedUp = batch.reorderPages(2, 0);
      expect(
        movedUp.pages.map((p) => p.name).toList(),
        ['c.jpg', 'a.jpg', 'b.jpg'],
      );
      expect(batch.pages.first.name, 'a.jpg');
    });

    test('updatePage replaces in place and ignores bad indexes', () {
      var batch = const DocumentBatch(id: 'b', pages: []);
      batch = batch.addPage(_page('a.jpg'));

      expect(batch.updatePage(-1, _page('x.jpg')), same(batch));
      expect(batch.updatePage(3, _page('x.jpg')), same(batch));

      final updated = batch.updatePage(0, _page('replaced.jpg'));
      expect(updated.pageCount, 1);
      expect(updated.pages.single.name, 'replaced.jpg');
      expect(batch.pages.single.name, 'a.jpg');
    });

    test('copyWith keeps undo/redo depths and untouched fields', () {
      final batch = DocumentBatch(
        id: 'b',
        pages: [_page('a.jpg')],
        createdAt: DateTime(2024, 1, 2),
        batchDirectory: '/tmp/batch',
        undoDepth: 3,
        redoDepth: 2,
      );

      final copy = batch.copyWith();
      expect(copy.id, 'b');
      expect(copy.batchDirectory, '/tmp/batch');
      expect(copy.createdAt, DateTime(2024, 1, 2));
      expect(copy.undoDepth, 3);
      expect(copy.redoDepth, 2);
      expect(copy.pages, same(batch.pages));
    });
  });

  group('DocumentBatchNotifier', () {
    test('initial state has no batch id and no history', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      expect(notifier.batchId, isNull);
      expect(notifier.canUndo, isFalse);
      expect(notifier.canRedo, isFalse);
      expect(container.read(documentBatchProvider).undoDepth, 0);
      expect(container.read(documentBatchProvider).redoDepth, 0);
    });

    test('addPage/undo/redo keep the exposed depths in sync', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      notifier.addPage(_page('a.jpg'));
      // Nothing is recorded while the batch is still empty.
      expect(notifier.canUndo, isFalse);

      notifier.addPage(_page('b.jpg'));
      expect(container.read(documentBatchProvider).pageCount, 2);
      expect(notifier.canUndo, isTrue);
      expect(container.read(documentBatchProvider).undoDepth, 1);

      notifier.undo();
      expect(container.read(documentBatchProvider).pageCount, 1);
      expect(container.read(documentBatchProvider).redoDepth, 1);
      expect(container.read(documentBatchProvider).undoDepth, 0);

      // Undo on an empty stack is a no-op.
      notifier.undo();
      expect(container.read(documentBatchProvider).pageCount, 1);

      notifier.redo();
      expect(container.read(documentBatchProvider).pageCount, 2);
      expect(container.read(documentBatchProvider).undoDepth, 1);
      expect(container.read(documentBatchProvider).redoDepth, 0);
      expect(notifier.canRedo, isFalse);

      // Redo on an empty stack is a no-op.
      notifier.redo();
      expect(container.read(documentBatchProvider).pageCount, 2);
    });

    test('a new edit clears the redo stack', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      notifier.addPage(_page('a.jpg'));
      notifier.addPage(_page('b.jpg'));
      notifier.undo();
      expect(notifier.canRedo, isTrue);

      notifier.addPage(_page('c.jpg'));
      expect(notifier.canRedo, isFalse);
      expect(container.read(documentBatchProvider).redoDepth, 0);
    });

    test('undo history is capped at 20 steps', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      for (var i = 0; i < 30; i++) {
        notifier.addPage(_page('p$i.jpg'));
      }
      expect(container.read(documentBatchProvider).undoDepth, 20);
      expect(container.read(documentBatchProvider).pageCount, 30);
    });

    test('reorderPages and updatePage go through the notifier with undo', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      notifier.addPage(_page('a.jpg'));
      notifier.addPage(_page('b.jpg'));

      notifier.reorderPages(0, 2);
      expect(
        container.read(documentBatchProvider).pages.map((p) => p.name),
        ['b.jpg', 'a.jpg'],
      );

      notifier.updatePage(0, _page('renamed.jpg'));
      expect(container.read(documentBatchProvider).pages.map((p) => p.name),
          ['renamed.jpg', 'a.jpg']);

      notifier.undo();
      expect(container.read(documentBatchProvider).pages.map((p) => p.name),
          ['b.jpg', 'a.jpg']);
      notifier.undo();
      expect(container.read(documentBatchProvider).pages.map((p) => p.name),
          ['a.jpg', 'b.jpg']);
      notifier.undo();
      expect(container.read(documentBatchProvider).pageCount, 1);
      expect(notifier.canUndo, isFalse);
    });

    test('startNewBatch creates the batch directory and resets history',
        () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      notifier.addPage(_page('a.jpg'));
      notifier.addPage(_page('b.jpg'));
      expect(notifier.canUndo, isTrue);

      await notifier.startNewBatch();

      final batch = container.read(documentBatchProvider);
      expect(batch.id, isNotEmpty);
      expect(notifier.batchId, batch.id);
      expect(batch.pages, isEmpty);
      expect(batch.createdAt, isNotNull);
      expect(batch.batchDirectory, isNotNull);
      expect(Directory(batch.batchDirectory!).existsSync(), isTrue);
      expect(notifier.canUndo, isFalse);
      expect(notifier.canRedo, isFalse);
      expect(batch.undoDepth, 0);
      expect(batch.redoDepth, 0);
    });

    test('addPageFromPath copies into the batch directory', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final source = File('${tempRoot.path}/source.jpg')
        ..writeAsBytesSync(_jpg(48, 48));
      await notifier.addPageFromPath(source.path);

      final batch = container.read(documentBatchProvider);
      expect(batch.pageCount, 1);

      final page = batch.pages.first;
      expect(page.name, 'source.jpg');
      expect(page.isLoaded, isTrue);
      expect(page.filterType, FilterType.none);
      expect(page.path, isNot(source.path),
          reason: 'page must be stored inside the batch directory');
      expect(File(page.path).existsSync(), isTrue);
      expect(page.path, contains(batch.id));
      expect(
        img.decodeImage(File(page.path).readAsBytesSync())!.width,
        48,
      );
    });

    test('addPageFromPath ignores paths that do not exist', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      await notifier.addPageFromPath('${tempRoot.path}/missing.jpg');
      expect(container.read(documentBatchProvider).pageCount, 0);
    });

    test('removePage deletes the stored page file', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final source = File('${tempRoot.path}/page.jpg')
        ..writeAsBytesSync(_jpg(40, 40));
      await notifier.addPageFromPath(source.path);
      final storedPath = container.read(documentBatchProvider).pages.single.path;
      expect(File(storedPath).existsSync(), isTrue);

      await notifier.removePage(0);

      expect(container.read(documentBatchProvider).pageCount, 0);
      expect(File(storedPath).existsSync(), isFalse);
      expect(notifier.canUndo, isTrue);

      // Undo restores the page entry (the file itself stays deleted).
      notifier.undo();
      expect(container.read(documentBatchProvider).pageCount, 1);
    });

    test('replacePageFromPath swaps the page and removes the old file',
        () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final first = File('${tempRoot.path}/one.jpg')
        ..writeAsBytesSync(_jpg(40, 40));
      final second = File('${tempRoot.path}/two.jpg')
        ..writeAsBytesSync(_jpg(64, 64));

      await notifier.addPageFromPath(first.path);
      final oldPath = container.read(documentBatchProvider).pages.single.path;

      await notifier.replacePageFromPath(0, second.path);

      final batch = container.read(documentBatchProvider);
      expect(batch.pageCount, 1);
      expect(batch.pages.single.name, 'two.jpg');
      expect(p.basename(batch.pages.single.path), 'page_0.jpg',
          reason: 'the replacement reuses the same batch slot');
      expect(File(oldPath).existsSync(), isTrue);
      expect(img.decodeImage(File(batch.pages.single.path).readAsBytesSync())!
          .width,
          64,
          reason: 'the file content must be the replacement image');
    });

    test('updatePageAndPersist writes the visible bytes to the batch dir',
        () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final original = _jpg(40, 40, gray: 40);
      final edited = _jpg(40, 40, gray: 220);
      notifier.addPage(ScannedPage(
        path: '',
        name: 'p.jpg',
        sizeBytes: original.length,
        imageBytes: original,
        filteredBytes: edited,
        filterType: FilterType.lighten,
      ));

      await notifier.updatePageAndPersist(
        0,
        container.read(documentBatchProvider).pages.single
            .copyWith(filteredBytes: edited),
      );

      final page = container.read(documentBatchProvider).pages.single;
      expect(page.path, isNotEmpty);
      final persisted = img.decodeImage(File(page.path).readAsBytesSync())!;
      expect(persisted.getPixel(20, 20).r, greaterThan(150),
          reason: 'the edited (bright) pixels must be the ones persisted');
    });

    test('applyFilterToPage applies and clears filters', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final source = File('${tempRoot.path}/filter_me.jpg')
        ..writeAsBytesSync(_jpg(64, 64, gray: 120));
      await notifier.addPageFromPath(source.path);

      await notifier.applyFilterToPage(0, FilterType.grayscale);
      var page = container.read(documentBatchProvider).pages.single;
      expect(page.filterType, FilterType.grayscale);
      expect(page.filteredBytes, isNotNull);
      expect(page.displayBytes, isNot(same(page.imageBytes)));
      expect(
        container.read(editHistoryProvider).first.fileName,
        contains('Scan (Grayscale)'),
      );

      await notifier.applyFilterToPage(0, FilterType.none);
      page = container.read(documentBatchProvider).pages.single;
      expect(page.filterType, FilterType.none);
      expect(page.filteredBytes, isNull);
      expect(page.displayBytes, same(page.imageBytes));
    });

    test('applyFilterToPage skips unloaded or missing pages', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      // No pages at all.
      await notifier.applyFilterToPage(0, FilterType.lighten);
      expect(container.read(documentBatchProvider).pageCount, 0);

      // Page without decoded bytes.
      notifier.addPage(const ScannedPage(
        path: '/tmp/x.jpg',
        name: 'x.jpg',
        sizeBytes: 10,
      ));
      await notifier.applyFilterToPage(0, FilterType.lighten);
      expect(container.read(documentBatchProvider).pages.single.filteredBytes,
          isNull);
    });

    test('applyFilterToAllPages updates every page', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      notifier.addPage(_page('a.jpg', bytes: _jpg(32, 32, gray: 90)));
      notifier.addPage(_page('b.jpg', bytes: _jpg(32, 32, gray: 90)));

      await notifier.applyFilterToAllPages(FilterType.sepia);

      final batch = container.read(documentBatchProvider);
      expect(batch.pageCount, 2);
      for (final page in batch.pages) {
        expect(page.filterType, FilterType.sepia);
        expect(page.filteredBytes, isNotNull);
      }
    });

    test('clearBatch deletes storage and resets the batch', () async {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);
      await notifier.startNewBatch();

      final source = File('${tempRoot.path}/gone.jpg')
        ..writeAsBytesSync(_jpg(32, 32));
      await notifier.addPageFromPath(source.path);

      final batchDir = container.read(documentBatchProvider).batchDirectory!;
      expect(Directory(batchDir).existsSync(), isTrue);

      await notifier.clearBatch();

      final cleared = container.read(documentBatchProvider);
      expect(cleared.id, isEmpty);
      expect(cleared.pages, isEmpty);
      expect(cleared.batchDirectory, isNull);
      expect(notifier.batchId, isNull);
      expect(notifier.canUndo, isFalse);
      expect(Directory(batchDir).existsSync(), isFalse);
    });

    test('export bytes honour the watermark switch and index bounds', () {
      final container = newContainer();
      final notifier = container.read(documentBatchProvider.notifier);

      final payload = _jpg(32, 32);
      notifier.addPage(_page('a.jpg', bytes: payload));
      notifier.addPage(_page('b.jpg', bytes: payload));

      final all = notifier.getAllExportPageBytes(offWatermark);
      expect(all, hasLength(2));
      expect(all.first, container.read(documentBatchProvider).pages.first.displayBytes);

      final single = notifier.getExportPageBytes(0, offWatermark);
      expect(single, container.read(documentBatchProvider).pages.first.displayBytes);

      expect(notifier.getExportPageBytes(99, offWatermark), isEmpty);
      expect(notifier.getExportPageBytes(2, offWatermark), isEmpty);
      expect(notifier.getAllExportPageBytes(offWatermark), hasLength(2));
    });
  });
}
