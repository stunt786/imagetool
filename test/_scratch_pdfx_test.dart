import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/pdf_service.dart';
import 'package:pixeltools/features/pdf_viewer/presentation/pdf_viewer_screen.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

const MethodChannel pdfxChannel = MethodChannel('io.scer.pdf_renderer');

/// Installs a fake pdfx renderer that reports [pageCount] pages and renders
/// solid-colour PNG pages. Returns the list of recorded method calls.
List<MethodCall> installPdfxMock({required int pageCount}) {
  final log = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pdfxChannel, (call) async {
    log.add(call);
    switch (call.method) {
      case 'open.document.file':
      case 'open.document.asset':
      case 'open.document.data':
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
      case 'close.document':
      case 'close.page':
        return null;
      default:
        return null;
    }
  });
  return log;
}

void uninstallPdfxMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pdfxChannel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initial;
  late Directory tempDir;

  setUp(() async {
    initial = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform();
    tempDir = await Directory.systemTemp.createTemp('explore2_');
  });

  tearDown(() async {
    PathProviderPlatform.instance = initial;
    uninstallPdfxMock();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> makePdf(int pages, String name) async {
    final doc = syncfusion.PdfDocument();
    for (var i = 0; i < pages; i++) {
      doc.pages.add();
    }
    final b = await doc.save();
    doc.dispose();
    final p = '${tempDir.path}/$name';
    await File(p).writeAsBytes(b);
    return p;
  }

  test('convertPdfToImages with mocked pdfx', () async {
    installPdfxMock(pageCount: 3);
    final input = await makePdf(3, 'c.pdf');

    Object? zoneError;
    final paths = await runZonedGuarded(
      () => PdfService.instance.convertPdfToImages(
        inputPath: input,
        format: 'jpg',
        outputBaseName: 'explore',
        dpi: 72,
        onProgress: (p) {},
      ),
      (e, s) => zoneError = e,
    );

    // ignore: avoid_print
    print('ZONE ERROR: $zoneError');
    // ignore: avoid_print
    print('CONVERTED: $paths');
    for (final p in paths!) {
      final f = File(p);
      // ignore: avoid_print
      print('  ${f.path} size=${await f.length()}');
      final bytes = await f.readAsBytes();
      // ignore: avoid_print
      print('  magic=${bytes.take(3).toList()}');
      final dec = img.decodeImage(bytes);
      // ignore: avoid_print
      print('  decoded=${dec?.width}x${dec?.height}');
    }
  });

  test('convert with png + pageNumbers subset', () async {
    installPdfxMock(pageCount: 4);
    final input = await makePdf(4, 'c2.pdf');
    Object? zoneError;
    final paths = await runZonedGuarded(
      () => PdfService.instance.convertPdfToImages(
        inputPath: input,
        format: 'png',
        outputBaseName: 'subset',
        dpi: 144,
        pageNumbers: [2, 99],
      ),
      (e, s) => zoneError = e,
    );
    // ignore: avoid_print
    print('ZONE ERROR2: $zoneError');
    // ignore: avoid_print
    print('CONVERTED2: $paths (${paths?.length})');
  });

  testWidgets('viewer widget with mocked pdfx', (tester) async {
    installPdfxMock(pageCount: 5);
    final input = await makePdf(5, 'view.pdf');

    Object? zoneError;
    await runZonedGuarded(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewerScreen(filePath: input),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }, (e, s) => zoneError = e);

    // ignore: avoid_print
    print('VIEWER ZONE ERROR: $zoneError');
    // ignore: avoid_print
    print('VIEWER TEXT: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
    // ignore: avoid_print
    print('VIEWER HAS CIRCULAR: ${find.byType(CircularProgressIndicator).evaluate().length}');
  });
}
