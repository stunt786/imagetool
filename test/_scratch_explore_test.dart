import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:pixeltools/core/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initial;
  late Directory tempDir;

  setUp(() async {
    initial = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform();
    tempDir = await Directory.systemTemp.createTemp('explore_');
  });

  tearDown(() async {
    PathProviderPlatform.instance = initial;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('pdfx openFile behavior', () async {
    final doc = syncfusion.PdfDocument();
    doc.pages.add();
    doc.pages.add();
    final bytes = await doc.save();
    doc.dispose();
    final path = '${tempDir.path}/two.pdf';
    await File(path).writeAsBytes(bytes);

    try {
      final pdfDoc = await pdfx.PdfDocument.openFile(path);
      // ignore: avoid_print
      print('PDFX OK pages=${pdfDoc.pagesCount}');
      await pdfDoc.close();
    } catch (e) {
      // ignore: avoid_print
      print('PDFX ERROR: ${e.runtimeType}: $e');
    }
  });

  test('merge worker via compute', () async {
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

    final a = await makePdf(2, 'a.pdf');
    final b = await makePdf(3, 'b.pdf');
    final merged = await PdfService.isolateMergeWorker({
      'filePaths': [a, b],
      'applyWatermark': false,
    });
    final out = syncfusion.PdfDocument(inputBytes: merged);
    // ignore: avoid_print
    print('MERGED PAGES: ${out.pages.count}');
    out.dispose();

    final allPages = await PdfService.isolateSplitAllPagesWorker({
      'inputBytes': await File(a).readAsBytes(),
      'applyWatermark': false,
    });
    // ignore: avoid_print
    print('SPLIT PARTS: ${allPages.length}');

    final imgBytes = _pngBytes();
    final encoded = await PdfService.isolateEncodeImagesWorker({
      'renderedPages': [imgBytes],
      'format': 'jpg',
    });
    // ignore: avoid_print
    print('ENCODED: ${encoded.length} first=${encoded.first.length}');
    final encodedPng = await PdfService.isolateEncodeImagesWorker({
      'renderedPages': [imgBytes],
      'format': 'png',
    });
    // ignore: avoid_print
    print('ENCODED PNG: ${encodedPng.length} first=${encodedPng.first.length}');
  });

  test('compute runs isolateMergeWorker', () async {
    final doc = syncfusion.PdfDocument();
    doc.pages.add();
    final b = await doc.save();
    doc.dispose();
    final p = '${tempDir.path}/one.pdf';
    await File(p).writeAsBytes(b);
    final merged = await PdfService.isolateMergeWorker({
      'filePaths': [p, p],
      'applyWatermark': false,
    });
    final out = syncfusion.PdfDocument(inputBytes: merged);
    // ignore: avoid_print
    print('MERGED2 PAGES: ${out.pages.count}');
    out.dispose();
  });

  test('page count on corrupt input', () async {
    final p = '${tempDir.path}/bad.pdf';
    await File(p).writeAsBytes('not a pdf at all'.codeUnits);
    try {
      final count = await PdfService.instance.getPageCount(p);
      // ignore: avoid_print
      print('CORRUPT PAGECOUNT: $count');
    } catch (e) {
      // ignore: avoid_print
      print('CORRUPT ERROR: ${e.runtimeType}: $e');
    }
  });

  test('compute isolate works', () async {
    final result = await compute(_echoWorker, <String, dynamic>{'n': 7});
    // ignore: avoid_print
    print('COMPUTE RESULT: $result');
  });

  test('mergePdfs via PdfService with path provider', () async {
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

    final a = await makePdf(1, 'm1.pdf');
    final b = await makePdf(4, 'm2.pdf');
    final progresses = <double>[];
    final outPath = await PdfService.instance.mergePdfs(
      inputPaths: [a, b],
      outputBaseName: 'explore_merge',
      onProgress: progresses.add,
    );
    final outFile = File(outPath);
    // ignore: avoid_print
    print('MERGE OUT: exists=${await outFile.exists()} '
        'size=${await outFile.length()} progresses=$progresses');
    final doc = syncfusion.PdfDocument(inputBytes: await outFile.readAsBytes());
    // ignore: avoid_print
    print('MERGE PAGES: ${doc.pages.count}');
    doc.dispose();
  });
}

Future<int> _echoWorker(Map<String, dynamic> params) async {
  return params['n'] as int;
}

Uint8List _pngBytes() {
  final image = img.Image(width: 40, height: 30);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodePng(image));
}
