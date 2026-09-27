import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/files/notifiers/operation_library_notifier.dart';
import 'package:pixeltools/features/files/presentation/files_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory base;
  late OperationStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('files_ui_test_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    // Widget tests must not spawn isolates or hit path_provider.
    ThumbnailService.debugOverride = (_) async => null;
  });

  tearDown(() async {
    ThumbnailService.debugOverride = null;
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  Future<OperationFolder> seedOperation({
    required OperationKind kind,
    required List<String> fileNames,
    DateTime? at,
  }) async {
    final directory = await store.createOperationDirectory(kind, at: at);
    final operation = await store.beginOperation(
      kind: kind,
      directory: directory,
      expectedItems: fileNames.length,
      at: at,
    );
    for (var i = 0; i < fileNames.length; i++) {
      final path = '${directory.path}/${fileNames[i]}';
      await File(path).writeAsBytes(List<int>.filled(32 + i, 4));
      await store.addOutputFile(operationId: operation.id, filePath: path);
    }
    await store.markCompleted(operation.id);
    return operation;
  }

  /// The screens contain indeterminate progress indicators, so we pump a
  /// bounded number of frames instead of using `pumpAndSettle`.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  /// Real file I/O must run inside [WidgetTester.runAsync]; the fake-async
  /// zone used by `testWidgets` never completes plain dart:io futures.
  Future<OperationFolder> seed(
    WidgetTester tester, {
    required OperationKind kind,
    required List<String> fileNames,
    DateTime? at,
  }) async {
    late OperationFolder operation;
    await tester.runAsync(() async {
      operation = await seedOperation(kind: kind, fileNames: fileNames, at: at);
    });
    return operation;
  }

  Future<void> pumpFiles(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: FilesScreen()),
      ),
    );
    await settle(tester);
  }

  group('FilesScreen', () {
    testWidgets('shows the empty state when nothing has been processed',
        (tester) async {
      await pumpFiles(tester);

      expect(find.text('No files yet'), findsOneWidget);
      expect(
        find.textContaining('Your processed images and PDFs'),
        findsOneWidget,
      );
    });

    testWidgets('lists operations with their item count', (tester) async {
      await seed(tester, 
        kind: OperationKind.resize,
        fileNames: ['a.jpg', 'b.jpg', 'c.jpg'],
        at: DateTime(2026, 9, 27, 19, 15),
      );
      await seed(tester, 
        kind: OperationKind.imageToPdf,
        fileNames: ['report.pdf'],
        at: DateTime(2026, 9, 28, 10, 0),
      );
      await pumpFiles(tester);

      expect(find.textContaining('Resize —'), findsOneWidget);
      expect(find.textContaining('Image to PDF —'), findsOneWidget);
      // Date + item count row from the reference design.
      expect(find.textContaining('09/27/2026 19:15'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('search filters the list', (tester) async {
      await seed(tester, 
        kind: OperationKind.resize,
        fileNames: ['sunset.jpg'],
        at: DateTime(2026, 1, 2, 10),
      );
      await seed(tester, 
        kind: OperationKind.imageToPdf,
        fileNames: ['report.pdf'],
        at: DateTime(2026, 3, 4, 11),
      );
      await pumpFiles(tester);
      expect(find.textContaining('Resize —'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'pdf');
      // Search is debounced.
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      expect(find.textContaining('Image to PDF —'), findsOneWidget);
      expect(find.textContaining('Resize —'), findsNothing);
    });

    testWidgets('filter menu narrows by file type', (tester) async {
      await seed(tester, 
        kind: OperationKind.resize,
        fileNames: ['sunset.jpg'],
        at: DateTime(2026, 1, 2, 10),
      );
      await seed(tester, 
        kind: OperationKind.imageToPdf,
        fileNames: ['report.pdf'],
        at: DateTime(2026, 3, 4, 11),
      );
      await pumpFiles(tester);

      await tester.tap(find.textContaining('All ('));
      await settle(tester);
      await tester.tap(find.textContaining('PDFs (').last);
      await settle(tester);

      expect(find.textContaining('Image to PDF —'), findsOneWidget);
      expect(find.textContaining('Resize —'), findsNothing);
    });

    testWidgets('selecting an operation reveals the contextual actions',
        (tester) async {
      await seed(tester, 
        kind: OperationKind.resize,
        fileNames: ['a.jpg', 'b.jpg'],
      );
      await pumpFiles(tester);

      expect(find.text('Share'), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('opening an operation shows its numbered contents',
        (tester) async {
      await seed(tester, 
        kind: OperationKind.resize,
        fileNames: ['image_001.jpg', 'image_002.jpg'],
      );
      await pumpFiles(tester);

      await tester.tap(find.textContaining('Resize —'));
      await settle(tester);

      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.textContaining('Tap to open'), findsOneWidget);
    });

    testWidgets('grid view toggle renders cards', (tester) async {
      await seed(tester, 
        kind: OperationKind.collage,
        fileNames: ['collage.jpg'],
      );
      await pumpFiles(tester);

      await tester.tap(find.byTooltip('Grid view'));
      await settle(tester);

      expect(find.text('1 file(s)'), findsOneWidget);
      expect(find.byTooltip('List view'), findsOneWidget);
    });

    testWidgets('delete flow confirms and empties the list', (tester) async {
      final operation = await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['page_1.jpg'],
      );
      await pumpFiles(tester);
      expect(find.textContaining('Scan —'), findsOneWidget);

      // Selection bar -> Delete -> confirmation dialog.
      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.textContaining('will be removed'), findsOneWidget);

      // Confirming performs real file I/O, which must run outside the
      // fake-async zone; the list is expected to react to the store change.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FilesScreen)),
      );
      await tester.runAsync(
        () => container
            .read(operationLibraryProvider.notifier)
            .deleteOperation(operation.id),
      );
      await settle(tester);

      expect(store.operationCount, 0);
      expect(find.text('No files yet'), findsOneWidget);
    });
  });
}
