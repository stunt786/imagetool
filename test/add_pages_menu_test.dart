import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/camera/services/scanner_capability_service.dart';
import 'package:pixeltools/features/files/notifiers/operation_library_notifier.dart';
import 'package:pixeltools/features/files/presentation/operation_folder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoScanner implements ScannerCapabilityService {
  @override
  Future<bool> isGoogleDocumentScannerAvailable() async => false;
}

void main() {
  late Directory base;
  late OperationStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('add_pages_test_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    ThumbnailService.debugOverride = (_) async => null;
  });

  tearDown(() async {
    ThumbnailService.debugOverride = null;
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  Future<OperationFolder> seed({
    required OperationKind kind,
    required List<String> fileNames,
  }) async {
    final directory = await store.createOperationDirectory(kind);
    final operation = await store.beginOperation(
      kind: kind,
      directory: directory,
      expectedItems: fileNames.length,
    );
    for (final name in fileNames) {
      final path = '${directory.path}/$name';
      await File(path).writeAsBytes(List<int>.filled(48, 7));
      await store.addOutputFile(operationId: operation.id, filePath: path);
    }
    await store.markCompleted(operation.id);
    return operation;
  }

  Future<void> pumpFolder(
    WidgetTester tester,
    String operationId, {
    ScannerCapabilityService? capability,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationStoreProvider.overrideWithValue(store),
          if (capability != null)
            scannerCapabilityProvider.overrideWithValue(capability),
        ],
        child: MaterialApp(
          home: OperationFolderScreen(operationId: operationId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openOverflowMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('scan folder offers Add Pages in the overflow menu',
      (tester) async {
    late OperationFolder operation;
    await tester.runAsync(() async {
      operation = await seed(
        kind: OperationKind.scan,
        fileNames: ['scan_page_01.jpg'],
      );
    });
    await pumpFolder(tester, operation.id);

    await openOverflowMenu(tester);

    expect(find.text('Add Pages'), findsOneWidget);
  });

  testWidgets('non-scan folder does not offer Add Pages', (tester) async {
    late OperationFolder operation;
    await tester.runAsync(() async {
      operation = await seed(
        kind: OperationKind.resize,
        fileNames: ['image_001.jpg'],
      );
    });
    await pumpFolder(tester, operation.id);

    await openOverflowMenu(tester);

    expect(find.text('Add Pages'), findsNothing);
    expect(find.text('Rename folder'), findsOneWidget);
  });

  testWidgets('Add Pages explains when the scanner is unavailable',
      (tester) async {
    late OperationFolder operation;
    await tester.runAsync(() async {
      operation = await seed(
        kind: OperationKind.scan,
        fileNames: ['scan_page_01.jpg'],
      );
    });
    await pumpFolder(tester, operation.id, capability: _NoScanner());

    await openOverflowMenu(tester);
    await tester.tap(find.text('Add Pages'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(
      find.text('The document scanner is not available on this device.'),
      findsOneWidget,
    );
  });
}
