import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/files/notifiers/operation_library_notifier.dart';
import 'package:pixeltools/features/files/presentation/history_screen.dart';
import 'package:pixeltools/features/files/presentation/operation_folder_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory base;
  late OperationStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('history_ui_test_');
    store = OperationStore(baseDirectoryProvider: () async => base);
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
    List<String> tags = const [],
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
    if (tags.isNotEmpty) {
      await store.updateOperationTags(operation.id, tags);
    }
    await store.markCompleted(operation.id);
    return operation;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<OperationFolder> seed(
    WidgetTester tester, {
    required OperationKind kind,
    required List<String> fileNames,
    DateTime? at,
    List<String> tags = const [],
  }) async {
    late OperationFolder operation;
    await tester.runAsync(() async {
      operation = await seedOperation(
        kind: kind,
        fileNames: fileNames,
        at: at,
        tags: tags,
      );
    });
    return operation;
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpFolder(WidgetTester tester, String operationId) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: OperationFolderScreen(operationId: operationId),
        ),
      ),
    );
    await settle(tester);
  }

  group('HistoryScreen (history.jpg)', () {
    testWidgets('shows empty state when no operations exist', (tester) async {
      await pumpHistory(tester);
      expect(find.text('No history yet'), findsOneWidget);
    });

    testWidgets('lists operations with title, date, count, and checkbox',
        (tester) async {
      await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['scan_01.jpg'],
        at: DateTime(2026, 9, 16, 6, 44),
      );
      await pumpHistory(tester);

      expect(find.textContaining('Scan —'), findsOneWidget);
      expect(find.textContaining('09/16/2026 06:44'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('search box filters history list', (tester) async {
      await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['cam_01.jpg'],
      );
      await seed(
        tester,
        kind: OperationKind.imageToPdf,
        fileNames: ['doc.pdf'],
      );
      await pumpHistory(tester);

      expect(find.textContaining('Scan —'), findsOneWidget);
      expect(find.textContaining('Image to PDF —'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pdf');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);

      expect(find.textContaining('Image to PDF —'), findsOneWidget);
      expect(find.textContaining('Scan —'), findsNothing);
    });

    testWidgets('selection mode exposes Share, Save, Rename, Delete',
        (tester) async {
      await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['scan_01.jpg'],
      );
      await pumpHistory(tester);

      expect(find.text('Share'), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('OperationFolderScreen (prev.jpg & prev1.jpg)', () {
    testWidgets('displays numbered pages, collage promo card, and Ask AI button',
        (tester) async {
      final op = await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['page1.jpg', 'page2.jpg'],
      );
      await pumpFolder(tester, op.id);

      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('Try making a collage'), findsOneWidget);
      expect(find.text('Ask AI'), findsOneWidget);
      expect(find.text('Tags +'), findsOneWidget);
    });

    testWidgets('selection mode exposes bottom action bar options',
        (tester) async {
      final op = await seed(
        tester,
        kind: OperationKind.scan,
        fileNames: ['page1.jpg', 'page2.jpg'],
      );
      await pumpFolder(tester, op.id);

      // Long press page 01 to enter selection mode
      await tester.longPress(find.text('01'));
      await settle(tester);

      expect(find.text('Hold and drag to reorder'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save to Gallery'), findsOneWidget);
      expect(find.text('Move/Copy'), findsOneWidget);
      expect(find.text('Collage'), findsOneWidget);
      expect(find.text('Create PDF'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
