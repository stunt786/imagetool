// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/output_saver.dart';
import 'package:pixeltools/core/services/public_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late OperationStore store;
  late PathProviderPlatform initialPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('output_saver2_test_');
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(base.path);
    store = OperationStore(baseDirectoryProvider: () async => base);
    await store.load();
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  group('ensurePixelToolsPrefix', () {
    test('prefixes a plain file name', () {
      expect(ensurePixelToolsPrefix('photo.jpg'), 'pixeltools_photo.jpg');
      expect(ensurePixelToolsPrefix('report'), 'pixeltools_report');
    });

    test('never doubles an existing prefix', () {
      expect(ensurePixelToolsPrefix('pixeltools_photo.jpg'),
          'pixeltools_photo.jpg');
      expect(
          ensurePixelToolsPrefix('PIXELTOOLS_photo.jpg'), 'PIXELTOOLS_photo.jpg');
      expect(ensurePixelToolsPrefix('PixelTools_a.png'), 'PixelTools_a.png');
    });

    test('trims surrounding whitespace first', () {
      expect(ensurePixelToolsPrefix('  holiday.png  '), 'pixeltools_holiday.png');
      expect(ensurePixelToolsPrefix('   '), 'pixeltools_');
    });

    test('keeps only the base name of a path-like argument', () {
      expect(ensurePixelToolsPrefix('/tmp/exports/deep/photo.jpg'),
          'pixeltools_photo.jpg');
      expect(ensurePixelToolsPrefix('../escape.jpg'), 'pixeltools_escape.jpg');
      expect(ensurePixelToolsPrefix('..'), 'pixeltools_..');
    });
  });

  group('saveToolOutputs naming', () {
    test('writes every output with the pixeltools_ prefix', () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.resize,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            fileName: 'holiday.jpg',
          ),
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[4, 5, 6]),
            fileName: 'pixeltools_keep.png',
          ),
        ],
      );

      expect(outputs, hasLength(2));
      for (final output in outputs) {
        expect(path.basename(output.localPath), startsWith('pixeltools'));
        expect(File(output.localPath).existsSync(), isTrue);
      }
      expect(path.basename(outputs[0].localPath), 'pixeltools_holiday.jpg');
      expect(path.basename(outputs[1].localPath), 'pixeltools_keep.png');
      expect(store.operations.single.status, OperationStatus.completed);
    });

    test('strips directories from the entry name before writing', () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.convert,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[9]),
            fileName: '/var/tmp/sneaky.gif',
          ),
        ],
      );

      final written = File(outputs.single.localPath);
      expect(written.existsSync(), isTrue);
      expect(path.isWithin(base.path, written.path), isTrue,
          reason: 'outputs must land in the app-managed operations folder');
      expect(path.basename(written.path), 'pixeltools_sneaky.gif');
    });

    test('name collisions inside one run are resolved', () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.resize,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1]),
            fileName: 'same.jpg',
          ),
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[2]),
            fileName: 'same.jpg',
          ),
        ],
      );

      expect(outputs, hasLength(2));
      expect(outputs[0].localPath, isNot(outputs[1].localPath));
      expect(File(outputs[0].localPath).readAsBytesSync(), <int>[1]);
      expect(File(outputs[1].localPath).readAsBytesSync(), <int>[2]);
      expect(store.filesFor(store.operations.single.id), hasLength(2));
    });

    test('publishes the base name of the written file', () async {
      final outputs = await saveToolOutputs(
        store,
        kind: OperationKind.imageToPdf,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1]),
            fileName: 'scan.pdf',
            publicKind: PublicFileKind.image,
          ),
        ],
      );

      // Off Android publishing is a pass-through, so the local file doubles
      // as the public destination.
      expect(outputs.single.publicPath, outputs.single.localPath);
      expect(path.basename(outputs.single.localPath), 'pixeltools_scan.pdf');
    });
  });

  group('saveToolOutputs failure handling', () {
    test('an empty byte payload falls back to staging and still fails loudly',
        () async {
      final staging = Directory(path.join(base.path, 'staging'));

      await expectLater(
        saveToolOutputs(
          store,
          kind: OperationKind.resize,
          stagingDirectory: staging,
          entries: <OutputEntry>[
            OutputEntry.bytes(
              bytes: Uint8List.fromList(<int>[]),
              fileName: 'broken.jpg',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a store failure re-runs the whole batch into staging with the '
        'prefix applied', () async {
      final broken = OperationStore(
        baseDirectoryProvider: () async => throw StateError('store down'),
      );
      final staging = Directory(path.join(base.path, 'staging'));

      final outputs = await saveToolOutputs(
        broken,
        kind: OperationKind.pdfMerge,
        stagingDirectory: staging,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[1, 2]),
            fileName: 'merged.pdf',
          ),
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[3, 4]),
            fileName: 'also.pdf',
          ),
        ],
      );

      expect(outputs, hasLength(2));
      for (final output in outputs) {
        expect(output.localPath, startsWith(staging.path));
        expect(path.basename(output.localPath), startsWith('pixeltools'));
        expect(File(output.localPath).existsSync(), isTrue);
      }
      expect(broken.operations, isEmpty);
    });

    test('a missing staging directory falls back to the documents folder',
        () async {
      final broken = OperationStore(
        baseDirectoryProvider: () async => throw StateError('store down'),
      );

      final outputs = await saveToolOutputs(
        broken,
        kind: OperationKind.resize,
        entries: <OutputEntry>[
          OutputEntry.bytes(
            bytes: Uint8List.fromList(<int>[7]),
            fileName: 'no_staging.jpg',
          ),
        ],
      );

      expect(outputs, hasLength(1));
      expect(File(outputs.single.localPath).existsSync(), isTrue);
      expect(outputs.single.publicPath, outputs.single.localPath);
    });

    test('a vanished source file surfaces a StateError', () async {
      final staging = Directory(path.join(base.path, 'staging2'));
      await expectLater(
        saveToolOutputs(
          store,
          kind: OperationKind.pdfCompress,
          stagingDirectory: staging,
          entries: <OutputEntry>[
            OutputEntry.file(
              sourcePath: path.join(base.path, 'missing.pdf'),
              fileName: 'missing.pdf',
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
