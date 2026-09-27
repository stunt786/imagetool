import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory base;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('opstore_test_');
  });

  tearDown(() async {
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  OperationStore makeStore() =>
      OperationStore(baseDirectoryProvider: () async => base);

  Future<String> writeFile(Directory dir, String name, {int size = 24}) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List<int>.filled(size, 7));
    return file.path;
  }

  Future<Directory> createImageFile(Directory dir, String name) async {
    final image = img.Image(width: 300, height: 200);
    img.fill(image, color: img.ColorRgb8(90, 140, 200));
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 85)),
    );
    return dir;
  }

  group('OperationStore — folders and transactions', () {
    test('creates a per-tool, timestamped directory', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.imageToPdf,
        at: DateTime(2026, 9, 27, 19, 15, 30),
      );

      expect(await directory.exists(), isTrue);
      expect(
        directory.path,
        contains('operations${Platform.pathSeparator}Image_to_PDF'),
      );
      expect(directory.path, endsWith('20260927_191530'));
    });

    test('groups every output of one run under a single operation', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.resize,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.resize,
        directory: directory,
        expectedItems: 3,
      );

      expect(operation.status, OperationStatus.processing);
      expect(operation.displayName, startsWith('Resize —'));

      for (var i = 1; i <= 3; i++) {
        final filePath = await writeFile(directory, 'image_00$i.jpg');
        await store.addOutputFile(
          operationId: operation.id,
          filePath: filePath,
        );
      }
      await store.markCompleted(operation.id);

      final completed = store.operationById(operation.id)!;
      expect(completed.status, OperationStatus.completed);
      expect(completed.isComplete, isTrue);
      expect(completed.itemCount, 3);
      expect(store.filesFor(operation.id).length, 3);
      expect(store.filesFor(operation.id).first.isImage, isTrue);
    });

    test('metadata survives a restart', () async {
      final first = makeStore();
      final directory = await first.createOperationDirectory(
        OperationKind.collage,
      );
      final operation = await first.beginOperation(
        kind: OperationKind.collage,
        directory: directory,
        expectedItems: 1,
      );
      final filePath = await writeFile(directory, 'collage.jpg');
      await first.addOutputFile(operationId: operation.id, filePath: filePath);
      await first.markCompleted(operation.id);

      // A brand new store instance hydrates from persisted metadata.
      final second = makeStore();
      await second.load();
      expect(second.operationCount, 1);
      expect(second.fileCount, 1);
      final restored = second.operationById(operation.id);
      expect(restored, isNotNull);
      expect(restored!.status, OperationStatus.completed);
      expect(restored.itemCount, 1);
      expect(second.filesFor(operation.id).single.fileName, 'collage.jpg');
    });

    test('a failed run keeps its partial output and records the error',
        () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.imageToPdf,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.imageToPdf,
        directory: directory,
        expectedItems: 5,
      );
      final filePath = await writeFile(directory, 'partial.pdf');
      await store.addOutputFile(operationId: operation.id, filePath: filePath);
      await store.markFailed(operation.id, 'Image 3 could not be read');

      final failed = store.operationById(operation.id)!;
      expect(failed.status, OperationStatus.failed);
      expect(failed.isIncomplete, isTrue);
      expect(failed.errorMessage, 'Image 3 could not be read');
      expect(store.filesFor(operation.id).length, 1);
      expect(File(filePath).existsSync(), isTrue);
    });

    test('refuses to overwrite an existing output', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.convert,
      );
      await writeFile(directory, 'photo.jpg');

      final second = await store.resolveOutputPath(directory, 'photo.jpg');
      expect(second, endsWith('photo_1.jpg'));
      final third = await store.resolveOutputPath(directory, 'photo.jpg');
      expect(third, endsWith('photo_1.jpg'));

      await File(second).writeAsBytes(List<int>.filled(4, 1));
      final fourth = await store.resolveOutputPath(directory, 'photo.jpg');
      expect(fourth, endsWith('photo_2.jpg'));
    });

    test('deleting an operation removes its folder and records', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.scan,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.scan,
        directory: directory,
      );
      final filePath = await writeFile(directory, 'page_1.jpg');
      await store.addOutputFile(operationId: operation.id, filePath: filePath);
      await store.markCompleted(operation.id);
      expect(await directory.exists(), isTrue);

      final deleted = await store.deleteOperation(operation.id);
      expect(deleted, isTrue);
      expect(store.operationCount, 0);
      expect(store.fileCount, 0);
      expect(await directory.exists(), isFalse);
    });

    test('deleting a single file keeps the operation', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.resize,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.resize,
        directory: directory,
      );
      final first = await writeFile(directory, 'a.jpg');
      final second = await writeFile(directory, 'b.jpg');
      final itemA = await store.addOutputFile(
        operationId: operation.id,
        filePath: first,
      );
      await store.addOutputFile(operationId: operation.id, filePath: second);

      await store.deleteFile(itemA!.id);
      expect(store.filesFor(operation.id).length, 1);
      expect(File(first).existsSync(), isFalse);
      expect(store.operationById(operation.id)!.itemCount, 1);
    });

    test('pruneMissing drops records whose folder disappeared', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.resize,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.resize,
        directory: directory,
      );
      await store.markCompleted(operation.id);

      await directory.delete(recursive: true);
      final removed = await store.pruneMissing();
      expect(removed, 1);
      expect(store.operationCount, 0);
    });
  });

  group('OperationStore — rename', () {
    test('normalizeRename never doubles the extension', () {
      expect(OperationStore.normalizeRename('holiday', 'photo.jpg'),
          'holiday.jpg');
      expect(OperationStore.normalizeRename('holiday.jpg', 'photo.jpg'),
          'holiday.jpg');
      expect(OperationStore.normalizeRename('holiday.jpg.jpg', 'photo.jpg'),
          'holiday.jpg');
      expect(OperationStore.normalizeRename('  ', 'photo.jpg'), 'untitled.jpg');
      expect(OperationStore.normalizeRename('a/b:c*', 'doc.pdf'), 'a_b_c_.pdf');
      expect(OperationStore.normalizeRename('notes', 'report.pdf'), 'notes.pdf');
    });

    test('renames a file on disk and in metadata', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.resize,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.resize,
        directory: directory,
      );
      final path = await writeFile(directory, 'image_001.jpg');
      final item = await store.addOutputFile(
        operationId: operation.id,
        filePath: path,
      );

      final renamed = await store.renameFile(item!.id, 'Cover photo');
      expect(renamed, isTrue);
      final updated = store.fileById(item.id)!;
      expect(updated.fileName, 'Cover photo.jpg');
      expect(File(updated.path).existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
    });

    test('renames an operation label without touching the directory', () async {
      final store = makeStore();
      final directory = await store.createOperationDirectory(
        OperationKind.collage,
      );
      final operation = await store.beginOperation(
        kind: OperationKind.collage,
        directory: directory,
      );

      final ok = await store.renameOperation(operation.id, 'Trip collage');
      expect(ok, isTrue);
      final updated = store.operationById(operation.id)!;
      expect(updated.displayName, 'Trip collage');
      expect(updated.directoryPath, directory.path);

      expect(await store.renameOperation(operation.id, '   '), isFalse);
    });
  });

  group('OperationStore — search, filter, sort', () {
    Future<OperationStore> seed() async {
      final store = makeStore();
      final resizeDir = await store.createOperationDirectory(
        OperationKind.resize,
        at: DateTime(2026, 1, 2, 10),
      );
      final resize = await store.beginOperation(
        kind: OperationKind.resize,
        directory: resizeDir,
        at: DateTime(2026, 1, 2, 10),
      );
      await store.addOutputFile(
        operationId: resize.id,
        filePath: await writeFile(resizeDir, 'sunset.jpg', size: 100),
      );
      await store.markCompleted(resize.id);

      final pdfDir = await store.createOperationDirectory(
        OperationKind.imageToPdf,
        at: DateTime(2026, 3, 4, 11),
      );
      final pdf = await store.beginOperation(
        kind: OperationKind.imageToPdf,
        directory: pdfDir,
        at: DateTime(2026, 3, 4, 11),
      );
      await store.addOutputFile(
        operationId: pdf.id,
        filePath: await writeFile(pdfDir, 'report.pdf', size: 500),
      );
      await store.markCompleted(pdf.id);
      return store;
    }

    test('filters by file type', () async {
      final store = await seed();
      expect(store.queryFiles(filter: FileFilter.pdfs).single.fileName,
          'report.pdf');
      expect(store.queryFiles(filter: FileFilter.images).single.fileName,
          'sunset.jpg');
      expect(store.queryFiles().length, 2);
    });

    test('searches file names and operation labels', () async {
      final store = await seed();
      expect(store.queryFiles(search: 'sun').single.fileName, 'sunset.jpg');
      expect(store.queryFiles(search: 'report').length, 1);
      expect(store.queryFiles(search: 'nothing-here'), isEmpty);
      expect(store.queryOperations(search: 'pdf').length, 1);
      expect(store.queryOperations(search: 'resize').length, 1);
    });

    test('sorts by date, name and size', () async {
      final store = await seed();
      expect(store.queryFiles(sort: FileSortOrder.newestFirst).first.fileName,
          'report.pdf');
      expect(store.queryFiles(sort: FileSortOrder.oldestFirst).first.fileName,
          'sunset.jpg');
      expect(store.queryFiles(sort: FileSortOrder.nameAsc).first.fileName,
          'report.pdf');
      expect(store.queryFiles(sort: FileSortOrder.sizeDesc).first.fileName,
          'report.pdf');
      expect(store.queryFiles(sort: FileSortOrder.sizeAsc).first.fileName,
          'sunset.jpg');
      expect(store.queryOperations(sort: FileSortOrder.oldestFirst).first.kind,
          OperationKind.resize);
    });

    test('filters files by operation', () async {
      final store = await seed();
      final resize = store
          .queryOperations()
          .firstWhere((o) => o.kind == OperationKind.resize);
      final items = store.queryFiles(operationId: resize.id);
      expect(items.single.fileName, 'sunset.jpg');
      expect(store.queryOperations(filter: FileFilter.pdfs).single.kind,
          OperationKind.imageToPdf);
    });
  });

  group('OperationFolder helpers', () {
    test('builds a readable display name', () {
      final name = OperationFolder.buildDisplayName(
        OperationKind.imageToPdf,
        DateTime(2026, 9, 27, 19, 15),
      );
      expect(name, 'Image to PDF — 27 Sep 2026, 7:15 PM');
    });

    test('formats midnight and noon correctly', () {
      expect(
        OperationFolder.buildDisplayName(
            OperationKind.scan, DateTime(2026, 1, 1, 0, 5)),
        contains('12:05 AM'),
      );
      expect(
        OperationFolder.buildDisplayName(
            OperationKind.scan, DateTime(2026, 1, 1, 12, 30)),
        contains('12:30 PM'),
      );
    });

    test('json round-trips', () {
      final original = OperationFolder(
        id: 'op_1',
        kind: OperationKind.pdfMerge,
        displayName: 'Merge',
        directoryPath: '/tmp/x',
        createdAt: DateTime(2026, 5, 5),
        modifiedAt: DateTime(2026, 5, 6),
        itemCount: 2,
        status: OperationStatus.completed,
      );
      final restored = OperationFolder.fromJson(original.toJson())!;
      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.status, original.status);
      expect(restored.itemCount, 2);
      expect(restored.createdAt, original.createdAt);
    });
  });

  group('ThumbnailService', () {
    test('generates, caches and invalidates previews', () async {
      final cacheDir = Directory('${base.path}/thumbcache');
      final service = ThumbnailService(
        cacheDirectoryProvider: () async => cacheDir,
      );
      final imageDir = await Directory('${base.path}/images').create();
      await createImageFile(imageDir, 'photo.jpg');
      final source = File('${imageDir.path}/photo.jpg');

      final first = await service.thumbnailFor(source.path);
      expect(first, isNotNull);
      final firstFile = File(first!);
      expect(await firstFile.exists(), isTrue);
      expect(await firstFile.length(), greaterThan(0));

      // Same file, same mtime => same cached path.
      final second = await service.thumbnailFor(source.path);
      expect(second, first);

      // Touching the file produces a new cache entry.
      await source.setLastModified(
        DateTime.now().add(const Duration(seconds: 5)),
      );
      final third = await service.thumbnailFor(source.path);
      expect(third, isNotNull);
      expect(third, isNot(first));
    });

    test('returns null for missing or invalid files', () async {
      final service = ThumbnailService(
        cacheDirectoryProvider: () async => Directory('${base.path}/tc2'),
      );
      expect(await service.thumbnailFor('${base.path}/nope.jpg'), isNull);

      final junk = File('${base.path}/junk.jpg');
      await junk.writeAsBytes(List<int>.filled(32, 3));
      expect(await service.thumbnailFor(junk.path), isNull);
    });

    test('clearCache removes generated previews', () async {
      final cacheDir = Directory('${base.path}/tc3');
      final service = ThumbnailService(
        cacheDirectoryProvider: () async => cacheDir,
      );
      final imageDir = await Directory('${base.path}/images2').create();
      await createImageFile(imageDir, 'a.jpg');
      await service.thumbnailFor('${imageDir.path}/a.jpg');
      expect(await cacheDir.exists(), isTrue);

      await service.clearCache();
      expect(await cacheDir.exists(), isFalse);
    });
  });
}
