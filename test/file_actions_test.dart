// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/features/files/services/file_actions.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class FakeSharePlatform extends Fake
    with MockPlatformInterfaceMixin
    implements SharePlatform {
  List<XFile>? lastSharedFiles;
  String? lastSubject;
  int shareCallCount = 0;
  bool shouldThrow = false;

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    if (shouldThrow) {
      throw PlatformException(code: 'share-failed');
    }
    shareCallCount++;
    lastSharedFiles = files;
    lastSubject = subject;
    return const ShareResult('success', ShareResultStatus.success);
  }
}

class FakeFilePickerPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FilePickerPlatform {
  String? nextResult;
  int saveCallCount = 0;
  String? lastSuggestedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveCallCount++;
    lastSuggestedName = fileName;
    return nextResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late BuildContext ctx;
  late FakeSharePlatform fakeShare;
  late SharePlatform initialShare;
  late FakeFilePickerPlatform fakePicker;
  late FilePickerPlatform initialPicker;

  setUp(() {
    fakeShare = FakeSharePlatform();
    initialShare = SharePlatform.instance;
    SharePlatform.instance = fakeShare;

    fakePicker = FakeFilePickerPlatform();
    initialPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = fakePicker;
  });

  tearDown(() {
    SharePlatform.instance = initialShare;
    FilePickerPlatform.instance = initialPicker;
  });

  setUp(() async {
    base = await Directory.systemTemp.createTemp('file_actions_test_');
  });

  tearDown(() async {
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  AppFileItem item(
    String name, {
    bool image = false,
    bool pdf = false,
    bool mustExist = true,
  }) {
    final path = '${base.path}/$name';
    if (mustExist) {
      File(path).writeAsBytesSync(List<int>.filled(16, 3));
    }
    final dot = name.lastIndexOf('.');
    return AppFileItem(
      id: 'id_$name',
      operationId: 'op_1',
      path: path,
      fileName: name,
      extension: dot > 0 ? name.substring(dot + 1).toLowerCase() : '',
      mimeType: 'application/octet-stream',
      sizeBytes: 16,
      createdAt: DateTime(2026, 9, 27, 19, 15),
      isImage: image,
      isPdf: pdf,
    );
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Runs [action] with real file I/O outside the fake-async zone, then pumps
  /// long enough for any SnackBar to be built.
  Future<void> act(
    WidgetTester tester,
    Future<void> Function(BuildContext) action,
  ) async {
    await tester.runAsync(() => action(ctx));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  group('FileActions.share', () {
    testWidgets('shows a message when none of the files exist', (tester) async {
      await pumpHarness(tester);

      await act(tester, (context) => FileActions.share(context, [
            item('gone_1.jpg', image: true, mustExist: false),
            item('gone_2.jpg', image: true, mustExist: false),
          ]));

      expect(find.text('Those files are no longer available.'), findsOneWidget);
      expect(fakeShare.shareCallCount, 0);
    });

    testWidgets('shares an existing file and passes its subject',
        (tester) async {
      await pumpHarness(tester);
      final photo = item('holiday.jpg', image: true);

      await act(tester, (context) => FileActions.share(context, [photo]));

      expect(fakeShare.shareCallCount, 1);
      expect(fakeShare.lastSharedFiles, hasLength(1));
      expect(fakeShare.lastSharedFiles!.single.path, photo.path);
      expect(fakeShare.lastSubject, 'holiday.jpg');
      expect(find.text('Those files are no longer available.'), findsNothing);
      expect(find.text('Could not share those files.'), findsNothing);
    });

    testWidgets('passes every existing file and drops missing ones',
        (tester) async {
      await pumpHarness(tester);
      final a = item('a.jpg', image: true);
      final b = item('b.jpg', image: true);
      final missing = item('c.jpg', image: true, mustExist: false);

      await act(
        tester,
        (context) => FileActions.share(context, [a, b, missing]),
      );

      expect(fakeShare.lastSharedFiles, hasLength(2));
      expect(
        fakeShare.lastSharedFiles!.map((f) => f.path),
        containsAll(<String>[a.path, b.path]),
      );
      // More than one item was handed in, so no single subject is used.
      expect(fakeShare.lastSubject, isNull);
    });

    testWidgets('surfaces a platform failure as a SnackBar', (tester) async {
      await pumpHarness(tester);
      fakeShare.shouldThrow = true;

      await act(
        tester,
        (context) => FileActions.share(context, [item('x.jpg', image: true)]),
      );

      expect(find.text('Could not share those files.'), findsOneWidget);
    });
  });

  group('FileActions.saveToGallery', () {
    testWidgets('rejects a selection without images', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) =>
            FileActions.saveToGallery(context, [item('report.pdf', pdf: true)]),
      );

      expect(
        find.text('Only images can be saved to the gallery.'),
        findsOneWidget,
      );
    });

    testWidgets('saves a single image', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) =>
            FileActions.saveToGallery(context, [item('one.jpg', image: true)]),
      );

      expect(find.text('Saved 1 image to the gallery.'), findsOneWidget);
    });

    testWidgets('saves several images', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) => FileActions.saveToGallery(context, [
          item('one.jpg', image: true),
          item('two.png', image: true),
        ]),
      );

      expect(find.text('Saved 2 images to the gallery.'), findsOneWidget);
    });

    testWidgets('reports partial failures', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) => FileActions.saveToGallery(context, [
          item('here.jpg', image: true),
          item('missing.jpg', image: true, mustExist: false),
        ]),
      );

      expect(
        find.text('Saved 1 image(s); 1 could not be saved.'),
        findsOneWidget,
      );
    });

    testWidgets('reports when every image is gone', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) => FileActions.saveToGallery(context, [
          item('missing_a.jpg', image: true, mustExist: false),
          item('missing_b.jpg', image: true, mustExist: false),
        ]),
      );

      expect(find.text('Could not save to the gallery.'), findsOneWidget);
    });
  });

  group('FileActions.exportPdfs', () {
    testWidgets('says so when the selection has no PDFs', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) => FileActions.exportPdfs(context, [item('a.jpg', image: true)]),
      );

      expect(find.text('There are no PDFs to export.'), findsOneWidget);
      expect(fakePicker.saveCallCount, 0);
    });

    testWidgets('exports through the save dialog', (tester) async {
      await pumpHarness(tester);
      fakePicker.nextResult = '/public/report.pdf';

      await act(
        tester,
        (context) =>
            FileActions.exportPdfs(context, [item('report.pdf', pdf: true)]),
      );

      expect(fakePicker.saveCallCount, 1);
      expect(fakePicker.lastSuggestedName, 'report.pdf');
      expect(find.text('Exported 1 PDF file(s).'), findsOneWidget);
    });

    testWidgets('treats a dismissed save dialog as a cancellation',
        (tester) async {
      await pumpHarness(tester);
      fakePicker.nextResult = null;

      await act(
        tester,
        (context) =>
            FileActions.exportPdfs(context, [item('report.pdf', pdf: true)]),
      );

      expect(find.text('Export cancelled.'), findsOneWidget);
    });
  });

  group('FileActions.exportFile', () {
    testWidgets('exports any file through the save dialog', (tester) async {
      await pumpHarness(tester);
      fakePicker.nextResult = '/public/document.tiff';

      await act(
        tester,
        (context) => FileActions.exportFile(
          context,
          item('document.tiff', image: true),
        ),
      );

      expect(fakePicker.saveCallCount, 1);
      expect(fakePicker.lastSuggestedName, 'document.tiff');
      expect(find.text('Exported "document.tiff".'), findsOneWidget);
    });

    testWidgets('treats a dismissed save dialog as a cancellation',
        (tester) async {
      await pumpHarness(tester);
      fakePicker.nextResult = null;

      await act(
        tester,
        (context) => FileActions.exportFile(
          context,
          item('document.tiff', image: true),
        ),
      );

      expect(find.text('Export cancelled.'), findsOneWidget);
    });
  });

  group('FileActions.save', () {
    testWidgets('routes images to the gallery only', (tester) async {
      await pumpHarness(tester);

      await act(
        tester,
        (context) =>
            FileActions.save(context, [item('photo.jpg', image: true)]),
      );

      expect(find.text('Saved 1 image to the gallery.'), findsOneWidget);
      expect(fakePicker.saveCallCount, 0);
    });

    testWidgets('routes PDFs to the export flow only', (tester) async {
      await pumpHarness(tester);
      fakePicker.nextResult = '/public/doc.pdf';

      await act(
        tester,
        (context) => FileActions.save(context, [item('doc.pdf', pdf: true)]),
      );

      expect(fakePicker.saveCallCount, 1);
      expect(find.text('Exported 1 PDF file(s).'), findsOneWidget);
    });

    testWidgets('does nothing for a mixed-free empty selection',
        (tester) async {
      await pumpHarness(tester);

      await act(tester, (context) => FileActions.save(context, const []));

      expect(find.byType(SnackBar), findsNothing);
      expect(fakePicker.saveCallCount, 0);
      expect(fakeShare.shareCallCount, 0);
    });
  });

  group('FileActions.confirmDelete', () {
    testWidgets('returns true when the user confirms', (tester) async {
      await pumpHarness(tester);
      bool? result;
      FileActions.confirmDelete(
        ctx,
        title: 'Delete "a.jpg"?',
        message: 'This will remove the file from this folder.',
      ).then((value) => result = value);
      await tester.pumpAndSettle();

      expect(find.text('Delete "a.jpg"?'), findsOneWidget);
      expect(
        find.text('This will remove the file from this folder.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false when the user cancels', (tester) async {
      await pumpHarness(tester);
      bool? result;
      FileActions.confirmDelete(ctx, title: 'T', message: 'M')
          .then((value) => result = value);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('returns false when the dialog is dismissed', (tester) async {
      await pumpHarness(tester);
      bool? result;
      FileActions.confirmDelete(ctx, title: 'T', message: 'M')
          .then((value) => result = value);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('FileActions.promptForName', () {
    testWidgets('rejects an empty name', (tester) async {
      await pumpHarness(tester);
      String? result = 'unset';
      FileActions.promptForName(
        ctx,
        title: 'Rename File',
        initialValue: 'photo.jpg',
      ).then((value) => result = value);
      await tester.pumpAndSettle();

      expect(find.text('Rename File'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        'photo.jpg',
      );

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a name'), findsOneWidget);
      expect(find.text('Rename File'), findsOneWidget);
      expect(result, 'unset');
    });

    testWidgets('returns the trimmed name', (tester) async {
      await pumpHarness(tester);
      String? result;
      FileActions.promptForName(
        ctx,
        title: 'Rename File',
        initialValue: 'photo.jpg',
      ).then((value) => result = value);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '  holiday  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(result, 'holiday');
      expect(find.text('Rename File'), findsNothing);
    });

    testWidgets('returns null when cancelled', (tester) async {
      await pumpHarness(tester);
      String? result = 'unset';
      FileActions.promptForName(ctx, title: 'Rename', initialValue: 'a.jpg')
          .then((value) => result = value);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

}
