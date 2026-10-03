import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/utils/file_type_detector.dart';
import 'package:pixeltools/features/files/presentation/file_preview_screen.dart';
import 'package:pixeltools/features/files/services/file_open_service.dart';
import 'package:pixeltools/features/pdf_viewer/presentation/pdf_viewer_screen.dart';
import 'package:pixeltools/shared/models/edit_history_item.dart';

const MethodChannel _pdfxChannel = MethodChannel('io.scer.pdf_renderer');

/// Installs a fake pdfx renderer so `PdfViewerScreen` can open a document
/// without touching the real plugin.
List<MethodCall> installPdfxMock({required int pageCount}) {
  final log = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pdfxChannel, (call) async {
    log.add(call);
    switch (call.method) {
      case 'open.document.file':
        return <dynamic, dynamic>{'id': 'doc-1', 'pagesCount': pageCount};
      case 'open.page':
        final args = call.arguments as Map<dynamic, dynamic>;
        return <dynamic, dynamic>{
          'id': 'page-${args['page']}',
          'width': 612,
          'height': 792,
        };
      case 'render':
        final args = call.arguments as Map<dynamic, dynamic>;
        final width = (args['width'] as num).toInt();
        final height = (args['height'] as num).toInt();
        final image = img.Image(width: width, height: height);
        img.fill(image, color: img.ColorRgb8(10, 120, 200));
        return <dynamic, dynamic>{
          'width': width,
          'height': height,
          'data': Uint8List.fromList(img.encodePng(image)),
        };
      default:
        return null;
    }
  });
  return log;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late BuildContext ctx;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('file_open_service_test_');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pdfxChannel, null);
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  String writeImage(String name) {
    final image = img.Image(width: 40, height: 30);
    img.fill(image, color: img.ColorRgb8(20, 140, 90));
    final path = '${base.path}/$name';
    File(path).writeAsBytesSync(img.encodeJpg(image));
    return path;
  }

  String writeDummy(String name) {
    final path = '${base.path}/$name';
    File(path).writeAsBytesSync(List<int>.filled(64, 7));
    return path;
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('FileOpenService.open — rejections', () {
    testWidgets('an empty path shows the missing-file message', (tester) async {
      await pumpHarness(tester);

      await tester.runAsync(() => FileOpenService.open(ctx, path: ''));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.text('This file is no longer available.'), findsOneWidget);
      expect(find.byType(FilePreviewScreen), findsNothing);
      expect(find.byType(PdfViewerScreen), findsNothing);
    });

    testWidgets('a path that no longer exists shows the same message',
        (tester) async {
      await pumpHarness(tester);

      await tester.runAsync(
        () => FileOpenService.open(ctx, path: '${base.path}/deleted.jpg'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.text('This file is no longer available.'), findsOneWidget);
      expect(find.byType(FilePreviewScreen), findsNothing);
    });

    testWidgets('unsupported extensions are refused', (tester) async {
      await pumpHarness(tester);
      final path = writeDummy('notes.txt');

      await tester.runAsync(() => FileOpenService.open(ctx, path: path));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        find.text('This file type cannot be opened in the app.'),
        findsOneWidget,
      );
      expect(find.byType(FilePreviewScreen), findsNothing);
    });

    testWidgets('an explicit other kind overrides a jpg name', (tester) async {
      await pumpHarness(tester);
      final path = writeImage('photo.jpg');

      await tester.runAsync(
        () => FileOpenService.open(ctx, path: path, kind: AppFileKind.other),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        find.text('This file type cannot be opened in the app.'),
        findsOneWidget,
      );
      expect(find.byType(FilePreviewScreen), findsNothing);
    });
  });

  group('FileOpenService.open — images', () {
    testWidgets('pushes the preview screen for an image', (tester) async {
      await pumpHarness(tester);
      final path = writeImage('sunset.jpg');

      var completed = false;
      FileOpenService.open(ctx, path: path, name: 'sunset.jpg')
          .then((_) => completed = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.byType(FilePreviewScreen), findsOneWidget);
      expect(find.text('sunset.jpg'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('opens the requested gallery item and clamps the index',
        (tester) async {
      await pumpHarness(tester);
      final first = writeImage('one.jpg');
      final second = writeImage('two.jpg');
      final third = writeImage('three.jpg');
      final items = <EditHistoryItem>[
        EditHistoryItem(
          fileName: 'one.jpg',
          toolUsed: 'Image',
          editedAt: DateTime(2026, 9, 1),
          filePath: first,
          thumbnailPath: first,
        ),
        EditHistoryItem(
          fileName: 'two.jpg',
          toolUsed: 'Image',
          editedAt: DateTime(2026, 9, 2),
          filePath: second,
          thumbnailPath: second,
        ),
        EditHistoryItem(
          fileName: 'three.jpg',
          toolUsed: 'Image',
          editedAt: DateTime(2026, 9, 3),
          filePath: third,
          thumbnailPath: third,
        ),
      ];

      FileOpenService.open(
        ctx,
        path: second,
        name: 'two.jpg',
        galleryItems: items,
        galleryIndex: 1,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(FilePreviewScreen), findsOneWidget);
      expect(find.text('two.jpg'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Out-of-range index falls back to the last gallery item.
      FileOpenService.open(
        ctx,
        path: second,
        name: 'two.jpg',
        galleryItems: items,
        galleryIndex: 99,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.text('three.jpg'), findsOneWidget);
    });

    testWidgets('falls back to a single item when no gallery is given',
        (tester) async {
      await pumpHarness(tester);
      final path = writeImage('lonely.png');

      FileOpenService.open(ctx, path: path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      // No explicit name: the file name is derived from the path.
      expect(find.text('lonely.png'), findsOneWidget);
    });
  });

  group('FileOpenService.open — pdfs', () {
    testWidgets('pushes the PDF viewer with the fake renderer running',
        (tester) async {
      installPdfxMock(pageCount: 4);
      await pumpHarness(tester);
      final path = writeDummy('contract.pdf');

      FileOpenService.open(ctx, path: path, name: 'contract.pdf');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.byType(PdfViewerScreen), findsOneWidget);
      expect(find.text('contract.pdf'), findsOneWidget);
      expect(find.byType(FilePreviewScreen), findsNothing);

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      // Page indicator rendered once the document reports its page count.
      expect(find.text('1 / 4'), findsOneWidget);
    });

    testWidgets('an explicit pdf kind overrides a non-pdf name',
        (tester) async {
      installPdfxMock(pageCount: 2);
      await pumpHarness(tester);
      final path = writeDummy('scanned.dat');

      FileOpenService.open(
        ctx,
        path: path,
        name: 'scanned.dat',
        kind: AppFileKind.pdf,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.byType(PdfViewerScreen), findsOneWidget);
      expect(find.text('scanned.dat'), findsOneWidget);
    });
  });
}
