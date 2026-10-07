import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_recorder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory base;
  late OperationStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('recorder_test_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    await store.load();
  });

  tearDown(() async {
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  group('OperationRecorder.start', () {
    test('creates a processing operation inside a fresh directory', () async {
      final session = await OperationRecorder(store)
          .start(OperationKind.resize, expectedItems: 3);

      expect(session.operation.status, OperationStatus.processing);
      expect(session.operation.expectedItems, 3);
      expect(Directory(session.directoryPath).existsSync(), isTrue);
      expect(path.isWithin(base.path, session.directoryPath), isTrue);
      expect(session.operationId, session.operation.id);
      expect(session.directory.path, session.directoryPath);
    });

    test('two sessions get their own operation ids', () async {
      final first =
          await OperationRecorder(store).start(OperationKind.convert);
      final second =
          await OperationRecorder(store).start(OperationKind.convert);

      expect(first.operationId, isNot(second.operationId));
      expect(store.operationCount, 2);
      // NOTE: folder names are only stamped to the second, so two runs of the
      // same tool started in the same second share one directory.
      expect(first.directoryPath, second.directoryPath);
    });
  });

  group('OperationSession.saveBytes', () {
    test('writes into the operation folder and records the file', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize);

      final item = await session.saveBytes(bytes(<int>[1, 2, 3]), 'a.jpg');

      expect(item, isNotNull);
      expect(File(item!.path).existsSync(), isTrue);
      expect(path.dirname(item.path), session.directoryPath);
      expect(item.fileName, 'a.jpg');
      expect(store.operationById(session.operationId)!.itemCount, 1);
      expect(store.filesFor(session.operationId), hasLength(1));
      expect(await File(item.path).readAsBytes(), <int>[1, 2, 3]);
      // The OperationFolder handed out by [OperationSession] is the snapshot
      // taken when the session started, so it never reflects later writes.
      expect(session.operation.itemCount, 0);
    });

    test('never overwrites a previous result', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize);

      final first = await session.saveBytes(bytes(<int>[1]), 'out.jpg');
      final second = await session.saveBytes(bytes(<int>[2]), 'out.jpg');

      expect(first!.path, isNot(second!.path));
      expect(second.path, endsWith('out_1.jpg'));
      expect(await File(first.path).readAsBytes(), <int>[1]);
      expect(await File(second.path).readAsBytes(), <int>[2]);
      expect(store.filesFor(session.operationId), hasLength(2));
    });

    test('carries thumbnail and page-count metadata', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.scan);
      final item = await session.saveBytes(
        bytes(<int>[7, 7]),
        'page_1.jpg',
        thumbnailPath: '/tmp/thumb.jpg',
        pageCount: 12,
      );

      expect(item!.thumbnailPath, '/tmp/thumb.jpg');
      expect(item.pageCount, 12);
      expect(item.isImage, isTrue);
    });
  });

  group('OperationSession.recordFile', () {
    test('copies a file written elsewhere into the operation folder',
        () async {
      final session =
          await OperationRecorder(store).start(OperationKind.pdfCompress);
      final outside = File(path.join(base.path, 'somewhere.pdf'));
      await outside.writeAsBytes(<int>[9, 9, 9], flush: true);

      final item = await session.recordFile(outside.path);

      expect(item, isNotNull);
      expect(path.dirname(item!.path), session.directoryPath);
      expect(item.path, isNot(outside.path));
      expect(File(item.path).existsSync(), isTrue);
      expect(await File(item.path).readAsBytes(), <int>[9, 9, 9]);
      // The source outside the folder is left alone by recordFile.
      expect(outside.existsSync(), isTrue);
    });

    test('uses displayName for the copied file name', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.pdfMerge);
      final outside = File(path.join(base.path, 'raw.pdf'));
      await outside.writeAsBytes(<int>[1], flush: true);

      final item = await session.recordFile(outside.path,
          displayName: 'Merged report', pageCount: 4);

      expect(item!.fileName, 'Merged report');
      expect(File(item.path).existsSync(), isTrue);
      expect(item.pageCount, 4);
    });

    test('returns null for a path that does not exist', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize);
      final item = await session.recordFile(path.join(base.path, 'gone.jpg'));
      expect(item, isNull);
      expect(store.filesFor(session.operationId), isEmpty);
    });

    test('a file already inside the folder is recorded where it is', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize);
      final inside = File(path.join(session.directoryPath, 'kept.png'));
      await inside.writeAsBytes(<int>[5], flush: true);

      final item = await session.recordFile(inside.path);
      expect(item!.path, inside.path);
      expect(store.filesFor(session.operationId), hasLength(1));
    });
  });

  group('OperationSession completion', () {
    test('complete() marks the run finished and keeps every output', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize,
              expectedItems: 2);
      await session.saveBytes(bytes(<int>[1]), 'one.jpg');
      await session.saveBytes(bytes(<int>[2]), 'two.jpg');

      await session.complete();

      final done = store.operationById(session.operationId)!;
      expect(done.status, OperationStatus.completed);
      expect(done.isComplete, isTrue);
      expect(done.itemCount, 2);
      expect(store.filesFor(session.operationId), hasLength(2));
      expect(File(path.join(done.directoryPath, 'one.jpg')).existsSync(),
          isTrue);
    });

    test('fail() keeps the partial output and records the message', () async {
      final session = await OperationRecorder(store)
          .start(OperationKind.imageToPdf, expectedItems: 5);
      await session.saveBytes(bytes(<int>[1, 2]), 'partial.pdf');

      await session.fail('Image 3 could not be read');

      final failed = store.operationById(session.operationId)!;
      expect(failed.status, OperationStatus.failed);
      expect(failed.isIncomplete, isTrue);
      expect(failed.errorMessage, 'Image 3 could not be read');
      expect(store.filesFor(session.operationId), hasLength(1));
      expect(
          File(path.join(failed.directoryPath, 'partial.pdf')).existsSync(),
          isTrue);
    });

    test('fail() after complete() rewrites the finished run', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.resize);
      await session.saveBytes(bytes(<int>[1]), 'a.jpg');
      await session.complete();
      await session.fail('late failure');

      final op = store.operationById(session.operationId)!;
      // No guard exists in OperationStore.markFailed, so a late failure
      // overwrites the completed status.
      expect(op.status, OperationStatus.failed);
      expect(op.errorMessage, 'late failure');
      expect(store.filesFor(session.operationId), hasLength(1));
    });

    test('cancel() marks the run cancelled', () async {
      final session =
          await OperationRecorder(store).start(OperationKind.convert);
      await session.cancel();

      final op = store.operationById(session.operationId)!;
      expect(op.status, OperationStatus.cancelled);
    });
  });

  group('recordCompletedOperation', () {
    test('records already-written files as one completed operation', () async {
      final dir = await Directory(path.join(base.path, 'exports')).create();
      final written = <String>[];
      for (var i = 0; i < 2; i++) {
        final f = File(path.join(dir.path, 'img_$i.jpg'));
        await f.writeAsBytes(<int>[i]);
        written.add(f.path);
      }

      final op = await recordCompletedOperation(
        store,
        OperationKind.resize,
        written,
      );

      expect(op, isNotNull);
      expect(op!.id, isNotEmpty);
      // The returned instance is the session snapshot from before any file
      // was recorded; the authoritative record lives in the store.
      expect(store.operationById(op.id)!.status, OperationStatus.completed);
      expect(store.operationById(op.id)!.itemCount, 2);
      expect(store.filesFor(op.id), hasLength(2));
    });

    test('returns null for an empty (or blank) file list', () async {
      expect(await recordCompletedOperation(store, OperationKind.resize, []),
          isNull);
      expect(
          await recordCompletedOperation(
              store, OperationKind.resize, <String>['', '']),
          isNull);
      expect(store.operationCount, 0);
    });

    test('never throws when the store is broken', () async {
      final broken = OperationStore(
        baseDirectoryProvider: () async => throw StateError('store down'),
      );
      final file = File(path.join(base.path, 'x.jpg'));
      await file.writeAsBytes(<int>[1]);

      final op = await recordCompletedOperation(
        broken,
        OperationKind.convert,
        <String>[file.path],
      );
      expect(op, isNull);
    });
  });

  group('OperationRecorder.open', () {
    test('reopens a finished operation so more files can be appended',
        () async {
      final session = await OperationRecorder(store).start(OperationKind.scan);
      await session.saveBytes(bytes(<int>[1]), 'scan_page_01.jpg');
      await session.complete();

      final reopened =
          await OperationRecorder(store).open(session.operationId);
      expect(reopened, isNotNull);

      final outside = File(path.join(base.path, 'new_page.jpg'));
      await outside.writeAsBytes(<int>[5, 6], flush: true);
      final item = await reopened!.recordFile(
        outside.path,
        displayName: 'scan_page_02.jpg',
      );

      expect(item, isNotNull);
      expect(item!.fileName, 'scan_page_02.jpg');
      expect(path.dirname(item.path), session.directoryPath);
      expect(File(item.path).readAsBytesSync(), <int>[5, 6]);
      expect(store.filesFor(session.operationId), hasLength(2));
      expect(store.operationById(session.operationId)!.itemCount, 2);
    });

    test('returns null when the operation no longer exists', () async {
      expect(await OperationRecorder(store).open('missing-op'), isNull);
    });
  });

  group('OutputNames', () {
    test('indexed builds zero-padded names', () {
      expect(OutputNames.indexed('jpg', 0), 'image_001.jpg');
      expect(OutputNames.indexed('.JPG', 8), 'image_009.jpg');
      expect(OutputNames.indexed('pdf', 11, pad: 2), 'image_12.pdf');
      expect(OutputNames.indexed('webp', 99), 'image_100.webp');
    });

    test('fromSource keeps a usable extension', () {
      expect(OutputNames.fromSource('holiday.jpg', 'png'), 'holiday.jpg');
      expect(OutputNames.fromSource('holiday', 'png'), 'holiday.png');
      expect(OutputNames.fromSource('  ', 'pdf'), 'output.pdf');
      expect(OutputNames.fromSource('.jpg', 'png'), '.jpg.png');
    });
  });
}
