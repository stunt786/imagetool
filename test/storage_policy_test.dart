import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/output_saver.dart';
import 'package:pixeltools/core/services/public_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PublicStorage save folder', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('setSaveTree persists uri and label, clearSaveTree removes both',
        () async {
      expect(await PublicStorage.loadTreeUri(), isNull);
      expect(await PublicStorage.loadTreeLabel(), isNull);

      await PublicStorage.setSaveTree(
        uri: 'content://tree/primary%3APixelTools',
        label: '/storage/emulated/0/PixelTools',
      );
      expect(
        await PublicStorage.loadTreeUri(),
        'content://tree/primary%3APixelTools',
      );
      expect(
        await PublicStorage.loadTreeLabel(),
        '/storage/emulated/0/PixelTools',
      );

      await PublicStorage.clearSaveTree();
      expect(await PublicStorage.loadTreeUri(), isNull);
      expect(await PublicStorage.loadTreeLabel(), isNull);
    });

    test('setSaveTree overwrites a previously stored folder', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PublicStorage.treeUriKey: 'content://tree/old',
        PublicStorage.treeLabelKey: '/old',
      });

      await PublicStorage.setSaveTree(
        uri: 'content://tree/new',
        label: '/new',
      );

      expect(await PublicStorage.loadTreeUri(), 'content://tree/new');
      expect(await PublicStorage.loadTreeLabel(), '/new');
    });

    test('kindForFileName routes photos to the gallery and the rest to '
        'documents', () {
      expect(
        PublicStorage.kindForFileName('shot.jpg'),
        PublicFileKind.image,
      );
      expect(
        PublicStorage.kindForFileName('scan.PNG'),
        PublicFileKind.image,
      );
      expect(
        PublicStorage.kindForFileName('frame.heic'),
        PublicFileKind.image,
      );
      expect(
        PublicStorage.kindForFileName('report.pdf'),
        PublicFileKind.document,
      );
      expect(
        PublicStorage.kindForFileName('notes.txt'),
        PublicFileKind.document,
      );
      expect(
        PublicStorage.kindForFileName('noextension'),
        PublicFileKind.document,
      );
    });

    test('publishFile returns the source path unchanged off Android',
        () async {
      final saved = await PublicStorage.publishFile(
        sourcePath: '/tmp/report.pdf',
        fileName: 'report.pdf',
        kind: PublicFileKind.document,
      );
      expect(saved, '/tmp/report.pdf');
    });
  });

  group('saveToolOutputs', () {
    late Directory base;
    late OperationStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      base = await Directory.systemTemp.createTemp('output_saver_test_');
      store = OperationStore(baseDirectoryProvider: () async => base);
      await store.load();
    });

    tearDown(() async {
      try {
        await base.delete(recursive: true);
      } catch (_) {}
    });

    test('empty entry list returns no outputs', () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.resize,
        entries: const <OutputEntry>[],
      );
      expect(outputs, isEmpty);
      expect(store.operations, isEmpty);
    });

    test('groups every output of one run in a single completed operation',
        () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.resize,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            fileName: 'first.png',
            publicKind: PublicFileKind.image,
          ),
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[4, 5, 6]),
            fileName: 'second.png',
            publicKind: PublicFileKind.image,
          ),
        ],
      );

      expect(outputs, hasLength(2));
      for (final output in outputs) {
        expect(File(output.localPath).existsSync(), isTrue);
        expect(output.localPath, contains('operations'));
        // Off Android publishing is a no-op: the local copy is the destination.
        expect(output.publicPath, output.localPath);
      }

      expect(store.operations, hasLength(1));
      final operation = store.operations.single;
      expect(operation.kind, OperationKind.resize);
      expect(operation.status, OperationStatus.completed);
      expect(operation.itemCount, 2);
      expect(
        File(path.join(operation.directoryPath, 'first.png')).existsSync(),
        isTrue,
      );
      expect(
        File(path.join(operation.directoryPath, 'second.png')).existsSync(),
        isTrue,
      );
    });

    test('moves a source file into the operation folder and removes it',
        () async {
      final source = File(path.join(base.path, 'working.pdf'));
      await source.writeAsBytes(<int>[9, 8, 7], flush: true);

      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.pdfCompress,
        entries: <OutputEntry>[
          OutputEntry.file(
            sourcePath: source.path,
            fileName: 'final.pdf',
          ),
        ],
      );

      expect(outputs, hasLength(1));
      expect(source.existsSync(), isFalse);
      expect(File(outputs.single.localPath).existsSync(), isTrue);
      expect(File(outputs.single.localPath).readAsBytesSync(), <int>[9, 8, 7]);
      expect(outputs.single.publicPath, outputs.single.localPath);
      expect(store.operations.single.status, OperationStatus.completed);
    });

    test('falls back to the staging directory when the store is unavailable',
        () async {
      final broken = OperationStore(
        baseDirectoryProvider: () async =>
            throw StateError('store is down'),
      );
      final staging = Directory(path.join(base.path, 'staging'));

      final outputs = await saveToolOutputs(
        broken,
        kind: OperationKind.resize,
        stagingDirectory: staging,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            fileName: 'fallback.png',
          ),
        ],
      );

      expect(outputs, hasLength(1));
      expect(outputs.single.localPath, startsWith(staging.path));
      expect(File(outputs.single.localPath).existsSync(), isTrue);
      // Off Android the local copy doubles as the published destination.
      expect(outputs.single.publicPath, outputs.single.localPath);
    });

    test('rejects empty bytes instead of writing a broken file', () async {
      final staging = Directory(path.join(base.path, 'staging'));
      await expectLater(
        saveToolOutputs(
          store,
          kind: OperationKind.resize,
          stagingDirectory: staging,
          entries: <OutputEntry>[
            OutputEntry.bytes(
              bytes: Uint8List.fromList(<int>[]),
              fileName: 'broken.png',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a source file that no longer exists', () async {
      final staging = Directory(path.join(base.path, 'staging'));
      await expectLater(
        saveToolOutputs(
          store,
          kind: OperationKind.pdfCompress,
          stagingDirectory: staging,
          entries: <OutputEntry>[
            OutputEntry.file(
              sourcePath: path.join(base.path, 'gone.pdf'),
              fileName: 'gone.pdf',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
