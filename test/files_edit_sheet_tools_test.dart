import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/operation_store_provider.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/camera/presentation/screens/magic_remove_screen.dart';
import 'package:pixeltools/features/files/presentation/file_crop_screen.dart';
import 'package:pixeltools/features/files/widgets/file_edit_sheet.dart';
import 'package:pixeltools/features/files/widgets/file_filter_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the Files → preview → "MODIFY WITH TOOLS" row.
///
/// Every tool must write its result back into the operation folder the file
/// came from, otherwise the open Files grid never changes and the tool looks
/// broken to the user.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late OperationStore store;
  late Directory sourceDir;
  late OperationFolder operation;
  late AppFileItem item;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('edit_sheet_tools_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    ThumbnailService.debugOverride = (_) async => null;

    sourceDir = await Directory.systemTemp.createTemp('edit_sheet_src_');
    final image = img.Image(width: 80, height: 60);
    img.fill(image, color: img.ColorRgb8(20, 120, 220));
    final sourcePath = '${sourceDir.path}/photo.jpg';
    await File(sourcePath).writeAsBytes(img.encodeJpg(image));

    final directory = await store.createOperationDirectory(
      OperationKind.imageEdit,
      at: DateTime(2026, 10, 4, 9, 30),
    );
    operation = await store.beginOperation(
      kind: OperationKind.imageEdit,
      directory: directory,
      expectedItems: 1,
      at: DateTime(2026, 10, 4, 9, 30),
    );
    final inFolder = '${directory.path}/photo.jpg';
    await File(sourcePath).copy(inFolder);
    await store.addOutputFile(operationId: operation.id, filePath: inFolder);
    await store.markCompleted(operation.id);
    item = store.filesFor(operation.id).first;
  });

  tearDown(() async {
    ThumbnailService.debugOverride = null;
    try {
      await base.delete(recursive: true);
    } catch (_) {}
    try {
      await sourceDir.delete(recursive: true);
    } catch (_) {}
  });

  List<String> folderFileNames() =>
      store.filesFor(operation.id).map((f) => f.fileName).toList();

  /// View metrics must be configured outside [WidgetTester.runAsync] so the
  /// render tree is laid out against the phone-sized viewport.
  void setUpPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Pumps a host widget. Must run inside [WidgetTester.runAsync] so the async
  /// work the widget kicks off in `initState` actually completes.
  Future<void> pumpHost(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Crop writes the cropped image into the same folder',
      (tester) async {
    setUpPhoneViewport(tester);

    late bool stillOpen;
    await tester.runAsync(() async {
      await pumpHost(tester, FileCropScreen(item: item));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Crop & Save'), findsOneWidget);

      await tester.tap(find.text('Crop & Save'));
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      stillOpen = tester.widgetList(find.byType(FileCropScreen)).isNotEmpty;
    });
    expect(stillOpen, isFalse, reason: 'crop screen never closed');

    final names = folderFileNames();
    expect(names, hasLength(2));
    expect(names.any((n) => n.contains('_cropped_')), isTrue,
        reason: 'cropped output missing from ${names.join(', ')}');
  });

  testWidgets('Filters write the filtered image into the same folder',
      (tester) async {
    setUpPhoneViewport(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));

      // _openFilter checks the file on disk before presenting the sheet, and
      // the sheet itself re-reads the file in initState - give both real time
      // to finish before interacting.
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Apply & Save'), findsOneWidget,
          reason: 'filter sheet did not open');
      expect(
        find.descendant(
            of: find.byType(FileFilterSheet),
            matching: find.byType(Image),
            matchRoot: true),
        findsOneWidget,
        reason: 'filter sheet never loaded the source image',
      );

      await tester.tap(find.text('Anti-Light'));
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();

      await tester.tap(find.text('Apply & Save'));
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    final names = folderFileNames();
    expect(names, hasLength(2));
    expect(names.any((n) => n.contains('_antiLight_')), isTrue,
        reason: 'filtered output missing from ${names.join(', ')}');
  });

  testWidgets('Magic Clean persists the cleaned bitmap into the folder',
      (tester) async {
    setUpPhoneViewport(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));

      final original = await File(item.path).readAsBytes();
      final cleaned = Uint8List.fromList(original);
      // Any byte difference is enough: the sheet only skips identical output.
      cleaned[cleaned.length - 1] = (cleaned[cleaned.length - 1] + 1) & 0xFF;

      // _openMagicRemove reads the file before pushing the editor.
      await tester.tap(find.text('Magic Clean'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MagicRemoveScreen), findsOneWidget,
          reason: 'magic clean screen did not open');

      final navContext = tester.element(find.byType(MagicRemoveScreen));
      Navigator.of(navContext).pop(cleaned);
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
    });

    final names = folderFileNames();
    expect(names, hasLength(2));
    expect(names.any((n) => n.contains('_cleaned_')), isTrue,
        reason: 'cleaned output missing from ${names.join(', ')}');
  });

  testWidgets('Resize writes the resized image into the same folder',
      (tester) async {
    setUpPhoneViewport(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));

      await tester.tap(find.text('Resize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Resize Image Preset'), findsOneWidget);

      await tester.tap(find.text('50% Scale (Half Size)'));
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
    });

    final names = folderFileNames();
    expect(names, hasLength(2));
    expect(names.any((n) => n.contains('_resized_')), isTrue,
        reason: 'resized output missing from ${names.join(', ')}');
  });

  testWidgets('Convert writes a TIFF into the same folder', (tester) async {
    setUpPhoneViewport(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));

      await tester.tap(find.text('Convert'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Convert to Format'), findsOneWidget);

      await tester.tap(find.text('TIFF'));
      await Future<void>.delayed(const Duration(seconds: 8));
      await tester.pump();
    });

    final names = folderFileNames();
    expect(names, hasLength(2));
    expect(names.any((n) => n.toLowerCase().endsWith('.tiff')), isTrue,
        reason: 'tiff output missing from ${names.join(', ')}');
  });

  testWidgets('tools stay visible without horizontal scrolling',
      (tester) async {
    setUpPhoneViewport(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));
      await tester.pump(const Duration(milliseconds: 300));

      final appSize = tester.getSize(find.byType(MaterialApp));
      for (final label in [
        'Crop',
        'Filters',
        'Magic Clean',
        'Resize',
        'Convert',
        'To PDF',
      ]) {
        final rect = tester.getRect(find.text(label));
        expect(rect.center.dx, lessThan(appSize.width),
            reason: '"$label" pill is off-screen horizontally');
        expect(rect.center.dy, lessThan(appSize.height),
            reason: '"$label" pill is off-screen vertically');
      }
    });
  });
}
