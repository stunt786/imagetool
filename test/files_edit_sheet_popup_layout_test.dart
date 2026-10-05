import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/operation_store_provider.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/files/widgets/file_edit_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pdf_ops_test_support.dart';

/// Regression tests for the popup windows opened from
/// Files → preview → edit → "MODIFY WITH TOOLS".
///
/// On a short screen (and with enlarged text / large system insets) the
/// Resize, Convert, Compress and Split sheets used to lay their content out
/// past the bottom edge of the display, so the last options were cut off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late OperationStore store;
  late Directory sourceDir;
  late OperationFolder operation;
  late AppFileItem imageItem;
  late AppFileItem pdfItem;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('popup_layout_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    ThumbnailService.debugOverride = (_) async => null;

    sourceDir = await Directory.systemTemp.createTemp('popup_layout_src_');
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
      expectedItems: 2,
      at: DateTime(2026, 10, 4, 9, 30),
    );
    final inFolder = '${directory.path}/photo.jpg';
    await File(sourcePath).copy(inFolder);
    await store.addOutputFile(operationId: operation.id, filePath: inFolder);

    final pdfPath = '${directory.path}/doc.pdf';
    await File(pdfPath).writeAsBytes(await buildPdfBytes(pages: 3));
    await store.addOutputFile(operationId: operation.id, filePath: pdfPath);
    await store.markCompleted(operation.id);

    imageItem = store
        .filesFor(operation.id)
        .firstWhere((f) => f.fileName == 'photo.jpg');
    pdfItem =
        store.filesFor(operation.id).firstWhere((f) => f.fileName == 'doc.pdf');
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

  /// A short phone with big system insets and enlarged text - the condition
  /// that used to push popup content off the bottom of the screen.
  void setUpShortPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAllTestValues();
    });
  }

  Future<void> pumpHost(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Drains every layout exception the edit sheet or one of its popups
  /// reported: on these viewports the sheet must lay out without errors.
  void expectNoLayoutErrors(WidgetTester tester, [String where = '']) {
    final errors = <Object>[];
    while (true) {
      final error = tester.takeException();
      if (error == null) break;
      errors.add(error);
    }
    expect(errors, isEmpty, reason: '[$where] layout errors: $errors');
  }

  /// Opens [tool], checks the popup scrolls instead of overflowing and that
  /// its last control is reachable inside the screen.
  Future<void> expectPopupFits(
    WidgetTester tester, {
    required String tool,
    required String title,
    required String lastControl,
  }) async {
    await tester.tap(find.text(tool));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final titleFinder = find.text(title);
    expect(titleFinder, findsOneWidget, reason: '"$tool" popup did not open');

    final container =
        find.ancestor(of: titleFinder, matching: find.byType(SafeArea)).first;
    final scroller = find.descendant(
        of: container, matching: find.byType(SingleChildScrollView));
    expect(scroller, findsOneWidget,
        reason: '"$tool" popup must scroll instead of overflowing');

    final screen = tester.getSize(find.byType(MaterialApp));
    expect(tester.getRect(container).bottom, lessThanOrEqualTo(screen.height),
        reason: '"$tool" popup extends below the screen');

    // Scroll to the end of the sheet so the last control is on screen.
    await tester.drag(scroller, const Offset(0, -800));
    await tester.pumpAndSettle();

    final box = tester.renderObject<RenderBox>(find.text(lastControl));
    final bottom =
        box.localToGlobal(Offset.zero).dy + box.size.height;
    expect(bottom, lessThanOrEqualTo(screen.height),
        reason: '"$lastControl" of the "$tool" popup is below the screen');

    Navigator.of(tester.element(titleFinder)).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('image tool popups stay on screen', (tester) async {
    setUpShortPhone(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: imageItem, onDeleted: () {}));
      expectNoLayoutErrors(tester);

      await expectPopupFits(tester,
          tool: 'Resize',
          title: 'Resize Image Preset',
          lastControl: 'Smart Compression (Best Quality / Size)');

      await expectPopupFits(tester,
          tool: 'Convert',
          title: 'Convert to Format',
          lastControl: 'BMP');
    });

    expectNoLayoutErrors(tester);
  });

  testWidgets('pdf tool popups stay on screen', (tester) async {
    setUpShortPhone(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: pdfItem, onDeleted: () {}));
      await tester.pump(const Duration(milliseconds: 400));
      expectNoLayoutErrors(tester);

      await expectPopupFits(tester,
          tool: 'Compress',
          title: 'Compress PDF Options',
          lastControl: 'Compress PDF');

      await expectPopupFits(tester,
          tool: 'Split',
          title: 'Split PDF Options',
          lastControl: 'Split PDF');
    });

    expectNoLayoutErrors(tester);
  });

  /// Share / Save / Rename / Delete used to overflow the row horizontally:
  /// 24px on a 360px-wide image sheet, 47px when the label became "Export"
  /// for a PDF. Each button now owns an [Expanded] slot and scales itself
  /// down, so no width or text scale can make the row overflow.
  testWidgets('file operations row fits a narrow screen', (tester) async {
    for (final (size, scale) in <(Size, double)>[
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 1.3),
      (const Size(320, 480), 1.0),
      (const Size(320, 480), 1.3),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.platformDispatcher.clearAllTestValues();
      });

      for (final (item, labels) in <(AppFileItem, List<String>)>[
        (imageItem, const ['Share', 'Save', 'Rename', 'Delete']),
        (pdfItem, const ['Share', 'Export', 'Rename', 'Delete']),
      ]) {
        await tester.runAsync(() async {
          await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));
        });
        expectNoLayoutErrors(tester);

        for (final label in labels) {
          final button = find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first;
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0),
              reason: '"$label" at ${size.width}w@$scale escapes left');
          expect(rect.right, lessThanOrEqualTo(size.width),
              reason: '"$label" at ${size.width}w@$scale escapes right');
          expect(rect.width, greaterThan(0),
              reason: '"$label" has no hit target');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  /// The sheet body used to overflow its own column vertically on short
  /// (and landscape) screens: the preview shrank to nothing and the tool
  /// buttons spilled past the bottom edge. It scrolls instead now.
  testWidgets('sheet body fits short and landscape screens', (tester) async {
    for (final (size, scale) in <(Size, double)>[
      (const Size(320, 480), 1.0),
      (const Size(320, 480), 1.3),
      (const Size(640, 360), 1.0),
      (const Size(360, 640), 1.3),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.platformDispatcher.clearAllTestValues();
      });

      for (final item in [imageItem, pdfItem]) {
        final where =
            '${size.width}x${size.height}@$scale ${item.fileName}';

        await tester.runAsync(() async {
          await pumpHost(tester, FileEditSheet(item: item, onDeleted: () {}));
        });
        await tester.pump(const Duration(milliseconds: 300));
        expectNoLayoutErrors(tester, where);

        // Scrolling the body must bring the file-operations row on screen.
        final body = find
            .descendant(
                of: find.byType(FileEditSheet),
                matching: find.byType(SingleChildScrollView))
            .first;
        await tester.drag(body, const Offset(0, -600));
        await tester.pumpAndSettle();

        final delete = tester.getRect(find.text('Delete'));
        expect(delete.bottom, lessThanOrEqualTo(size.height),
            reason: '[$where] Delete is not reachable by scrolling');
        expect(delete.top, greaterThanOrEqualTo(0),
            reason: '[$where] Delete scrolled past the top');
        expectNoLayoutErrors(tester, where);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });


  /// The "Save Pages as Images" sheet had no scroll container at all and its
  /// header/chip rows could run past the sheet on the right.
  testWidgets('pdf to images popup stays on screen', (tester) async {
    setUpShortPhone(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: pdfItem, onDeleted: () {}));
      await tester.pump(const Duration(milliseconds: 400));
      expectNoLayoutErrors(tester);

      await tester.tap(find.text('Save Pages as Images'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectNoLayoutErrors(tester, 'pdf-images opened');

      final title = find.text('Image Format');
      expect(title, findsOneWidget, reason: 'options sheet did not open');
      final scroller = find
          .ancestor(of: title, matching: find.byType(SingleChildScrollView))
          .first;
      expect(scroller, findsOneWidget,
          reason: 'the sheet must scroll instead of overflowing');

      final screen = tester.getSize(find.byType(MaterialApp));
      expect(tester.getRect(scroller).bottom, lessThanOrEqualTo(screen.height),
          reason: 'pdf-images sheet extends below the screen');

      // The From / To row only exists once a custom range is selected.
      await tester.tap(find.text('Custom Range'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutErrors(tester, 'pdf-images custom range');
      expect(find.text('From: '), findsOneWidget);

      await tester.drag(scroller, const Offset(0, -800));
      await tester.pumpAndSettle();
      final button = find.text('Convert & Save Images');
      final box = tester.renderObject<RenderBox>(button);
      final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
      expect(bottom, lessThanOrEqualTo(screen.height),
          reason: 'convert button is below the screen');

      Navigator.of(tester.element(title)).pop();
      await tester.pumpAndSettle();
    });

    expectNoLayoutErrors(tester);
  });

  /// The chunk and page-range rows are rendered only after a mode is picked,
  /// and they used to run past the sheet on the right at large text scale.
  testWidgets('split mode rows stay on screen', (tester) async {
    setUpShortPhone(tester);

    await tester.runAsync(() async {
      await pumpHost(tester, FileEditSheet(item: pdfItem, onDeleted: () {}));
      await tester.pump(const Duration(milliseconds: 400));
      expectNoLayoutErrors(tester);

      await tester.tap(find.text('Split'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expectNoLayoutErrors(tester, 'split opened');

      await tester.tap(find.text('By Page Chunks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutErrors(tester, 'split by chunks');
      expect(find.text('Pages per chunk: '), findsOneWidget);

      await tester.tap(find.text('Custom Page Range'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expectNoLayoutErrors(tester, 'split page range');
      expect(find.text('From: '), findsOneWidget);

      Navigator.of(tester.element(find.text('Split PDF Options'))).pop();
      await tester.pumpAndSettle();
    });

    expectNoLayoutErrors(tester);
  });

}
