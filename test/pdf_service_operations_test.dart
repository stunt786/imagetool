// Unit tests for the merge / split / convert code paths of PdfService that
// existing tests do not cover (pdf_compression_engine_test.dart only exercises
// the compression side).
//
// Fixtures are built with the Syncfusion engine, saved to a temp directory and
// round-tripped through the real implementation: every assertion checks page
// counts, byte sizes, file names or decoded pixels.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/pdf_service.dart';

import 'pdf_ops_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform initialPathProvider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_ops_service_');
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
    await Directory('${tempDir.path}/docs').create(recursive: true);
    await Directory('${tempDir.path}/tmp').create(recursive: true);
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    uninstallPdfxMock();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('PdfService.mergePdfs', () {
    test('merges two documents into one with the summed page count',
        () async {
      final a = await writePdf(tempDir, 'merge_a.pdf', pages: 2);
      final b = await writePdf(tempDir, 'merge_b.pdf', pages: 3);
      final progress = <double>[];

      final outPath = await PdfService.instance.mergePdfs(
        inputPaths: [a, b],
        outputBaseName: 'merge_ops',
        onProgress: progress.add,
      );

      final out = File(outPath);
      expect(await out.exists(), isTrue);
      expect(await out.length(), greaterThan(0));
      expect(
        String.fromCharCodes(await out.openRead(0, 4).fold<List<int>>(
            <int>[], (prev, chunk) => prev..addAll(chunk))),
        '%PDF',
      );
      expect(pageCountOf(await out.readAsBytes()), 5);
      expect(progress, [0.5, 1.0]);
      expect(outPath, contains('merge_ops'));
    });

    test('merges a single input and keeps its page count', () async {
      final a = await writePdf(tempDir, 'single.pdf', pages: 4);

      final outPath =
          await PdfService.instance.mergePdfs(inputPaths: [a], outputBaseName: 'solo');

      expect(pageCountOf(await File(outPath).readAsBytes()), 4);
      expect(File(outPath).parent.path, contains('PixelTools'));
    });

    test('rejects an empty input list', () async {
      await expectLater(
        () => PdfService.instance
            .mergePdfs(inputPaths: const [], outputBaseName: 'none'),
        throwsArgumentError,
      );
    });

    test('propagates the parse failure for corrupt input', () async {
      final bad = '${tempDir.path}/bad.pdf';
      await File(bad).writeAsBytes(corruptPdfBytes(), flush: true);

      await expectLater(
        () =>
            PdfService.instance.mergePdfs(inputPaths: [bad], outputBaseName: 'bad'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PdfService.splitPdfAllPages', () {
    test('writes one single-page PDF per source page', () async {
      final input = await writePdf(
        tempDir,
        'split_src.pdf',
        pageSizes: [
          const ui.Size(200, 200),
          const ui.Size(300, 300),
          const ui.Size(400, 400),
        ],
      );
      final progress = <double>[];

      final outputs = await PdfService.instance.splitPdfAllPages(
        inputPath: input,
        outputBaseName: 'all',
        onProgress: progress.add,
      );

      expect(outputs, hasLength(3));
      expect(progress, [1 / 3, 2 / 3, 1.0]);
      for (var i = 0; i < outputs.length; i++) {
        final file = File(outputs[i]);
        expect(await file.exists(), isTrue);
        expect(await file.length(), greaterThan(0));
        expect(outputs[i], contains('all_page_${i + 1}.pdf'));
        final doc = syncfusionDocOf(await file.readAsBytes());
        expect(doc.pages.count, 1);
        expect(doc.pages[0].size.width, closeTo(200 + i * 100, 0.01));
        doc.dispose();
      }
    });

    test('throws for corrupt input', () async {
      final bad = '${tempDir.path}/split_bad.pdf';
      await File(bad).writeAsBytes(corruptPdfBytes(), flush: true);

      await expectLater(
        () => PdfService.instance
            .splitPdfAllPages(inputPath: bad, outputBaseName: 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PdfService.extractPages', () {
    test('extracts the requested pages in the requested order', () async {
      final input = await writePdf(
        tempDir,
        'extract_src.pdf',
        pageSizes: [
          const ui.Size(210, 210),
          const ui.Size(320, 320),
          const ui.Size(430, 430),
          const ui.Size(540, 540),
        ],
      );
      final progress = <double>[];

      final outPath = await PdfService.instance.extractPages(
        inputPath: input,
        pageNumbers: [4, 2],
        outputBaseName: 'extract',
        onProgress: progress.add,
      );

      final doc = syncfusionDocOf(await File(outPath).readAsBytes());
      expect(doc.pages.count, 2);
      expect(doc.pages[0].size.width, closeTo(540, 0.01),
          reason: 'page 4 must come first as requested');
      expect(doc.pages[1].size.width, closeTo(320, 0.01));
      doc.dispose();
      expect(progress, [0.5, 1.0]);
      expect(outPath, contains('extract_extracted'));
    });

    test('rejects an empty page list', () async {
      final input = await writePdf(tempDir, 'extract_empty.pdf', pages: 2);

      await expectLater(
        () => PdfService.instance.extractPages(
          inputPath: input,
          pageNumbers: const [],
          outputBaseName: 'x',
        ),
        throwsArgumentError,
      );
    });

    test('rejects pages outside the document', () async {
      final input = await writePdf(tempDir, 'extract_range.pdf', pages: 4);

      await expectLater(
        PdfService.instance.extractPages(
          inputPath: input,
          pageNumbers: const [2, 9],
          outputBaseName: 'x',
        ),
        throwsA(predicate((e) => '$e'.contains('out of range (1-4)'))),
      );
    });
  });

  group('PdfService.splitPdfByChunk', () {
    test('splits five pages into chunks of two', () async {
      final input = await writePdf(tempDir, 'chunk_src.pdf', pages: 5);
      final progress = <double>[];

      final outputs = await PdfService.instance.splitPdfByChunk(
        inputPath: input,
        pageSize: 2,
        outputBaseName: 'chunk',
        onProgress: progress.add,
      );

      expect(outputs, hasLength(3));
      final counts = <int>[];
      for (final path in outputs) {
        expect(File(path).existsSync(), isTrue);
        final doc = syncfusionDocOf(await File(path).readAsBytes());
        counts.add(doc.pages.count);
        doc.dispose();
      }
      expect(counts, [2, 2, 1]);
      expect(progress.last, 1.0);
      expect(outputs.first, contains('chunk_part_1.pdf'));
      expect(outputs.last, contains('chunk_part_3.pdf'));
    });

    test('rejects a chunk size below one', () async {
      final input = await writePdf(tempDir, 'chunk_zero.pdf', pages: 3);

      await expectLater(
        () => PdfService.instance.splitPdfByChunk(
          inputPath: input,
          pageSize: 0,
          outputBaseName: 'x',
        ),
        throwsArgumentError,
      );
    });
  });

  group('PdfService.getPageCount', () {
    test('counts the pages of a real document', () async {
      final input = await writePdf(tempDir, 'count.pdf', pages: 7);
      expect(await PdfService.instance.getPageCount(input), 7);
    });

    test('throws for corrupt input', () async {
      final bad = '${tempDir.path}/count_bad.pdf';
      await File(bad).writeAsBytes(corruptPdfBytes(), flush: true);
      await expectLater(() => PdfService.instance.getPageCount(bad),
          throwsA(isA<ArgumentError>()));
    });

    test('throws when the file does not exist', () async {
      await expectLater(
        () => PdfService.instance.getPageCount('${tempDir.path}/absent.pdf'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('PdfService isolate workers', () {
    test('isolateMergeWorker merges raw bytes as well as file paths',
        () async {
      final two = await buildPdfBytes(pages: 2);
      final three = await buildPdfBytes(pages: 3);

      final merged = await PdfService.isolateMergeWorker(<String, dynamic>{
        'files': <Uint8List>[two, three],
        'applyWatermark': false,
      });

      expect(pageCountOf(merged), 5);
      expect(String.fromCharCodes(merged.take(4)), '%PDF');
    });

    test('isolateMergeWorker rejects a corrupt member file', () async {
      final good = await buildPdfBytes(pages: 1);
      final path = '${tempDir.path}/member.pdf';
      await File(path).writeAsBytes(good, flush: true);

      await expectLater(
        () => PdfService.isolateMergeWorker(<String, dynamic>{
          'filePaths': <String>['${tempDir.path}/nope.pdf'],
          'applyWatermark': false,
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).existsSync(), isTrue);
    });

    test('isolateExtractPagesWorker keeps the requested order', () async {
      final src = await buildPdfBytes(pageSizes: [
        const ui.Size(111, 111),
        const ui.Size(222, 222),
        const ui.Size(333, 333),
      ]);

      final out = await PdfService.isolateExtractPagesWorker(<String, dynamic>{
        'inputBytes': src,
        'pageNumbers': <int>[3, 1],
        'applyWatermark': false,
      });

      final doc = syncfusionDocOf(out);
      expect(doc.pages.count, 2);
      expect(doc.pages[0].size.width, closeTo(333, 0.01));
      expect(doc.pages[1].size.width, closeTo(111, 0.01));
      doc.dispose();
    });

    test('isolateExtractPagesWorker throws on an out-of-range page',
        () async {
      final src = await buildPdfBytes(pages: 2);

      await expectLater(
        () => PdfService.isolateExtractPagesWorker(<String, dynamic>{
          'inputBytes': src,
          'pageNumbers': <int>[3],
          'applyWatermark': false,
        }),
        throwsA(isA<RangeError>()),
      );
    });

    test('isolateSplitSelectedPagesWorker returns one PDF per page',
        () async {
      final src = await buildPdfBytes(pageSizes: [
        const ui.Size(150, 150),
        const ui.Size(250, 250),
        const ui.Size(350, 350),
      ]);

      final results = await PdfService.isolateSplitSelectedPagesWorker(
        <String, dynamic>{
          'inputBytes': src,
          'pageNumbers': <int>[1, 3],
          'applyWatermark': false,
        },
      );

      expect(results, hasLength(2));
      expect(pageCountOf(results[0]), 1);
      expect(pageCountOf(results[1]), 1);
      expect(syncfusionDocOf(results[0]).pages[0].size.width, closeTo(150, 0.01));
      expect(syncfusionDocOf(results[1]).pages[0].size.width, closeTo(350, 0.01));
    });

    test('isolateSplitByChunksWorker groups pages into chunks', () async {
      final src = await buildPdfBytes(pages: 5);

      final results = await PdfService.isolateSplitByChunksWorker(
        <String, dynamic>{
          'inputBytes': src,
          'pageSize': 3,
          'applyWatermark': false,
        },
      );

      expect(results, hasLength(2));
      expect(pageCountOf(results[0]), 3);
      expect(pageCountOf(results[1]), 2);
    });

    test('isolateEncodeImagesWorker re-encodes PNG input to jpg and png',
        () async {
      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(200, 30, 30));
      final png = Uint8List.fromList(img.encodePng(image));

      final jpgs = await PdfService.isolateEncodeImagesWorker(
        <String, dynamic>{'renderedPages': <Uint8List>[png], 'format': 'jpg'},
      );
      final pngs = await PdfService.isolateEncodeImagesWorker(
        <String, dynamic>{'renderedPages': <Uint8List>[png], 'format': 'png'},
      );

      expect(jpgs, hasLength(1));
      expect(jpgs.first.sublist(0, 3), [0xFF, 0xD8, 0xFF],
          reason: 'JPEG SOI marker');
      expect(pngs.first.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
          reason: 'PNG signature');
      expect(img.decodeImage(jpgs.first)!.width, 40);
      expect(img.decodeImage(pngs.first)!.height, 30);
    });

    test('isolateEncodeImagesWorker silently drops undecodable pages',
        () async {
      final results = await PdfService.isolateEncodeImagesWorker(
        <String, dynamic>{
          'renderedPages': <Uint8List>[Uint8List.fromList([1, 2, 3])],
          'format': 'png',
        },
      );
      expect(results, isEmpty);
    });
  });

  group('PdfService.convertPdfToImages', () {
    test('renders every page to JPEG at the requested dpi', () async {
      final zone = PdfxZone();
      final input = await writePdf(tempDir, 'img_src.pdf', pages: 3);
      final progress = <double>[];
      installPdfxMock(pageCount: 3);

      final outputs = await zone.guard(
        () => PdfService.instance.convertPdfToImages(
          inputPath: input,
          format: 'jpg',
          outputBaseName: 'pages',
          dpi: 72,
          onProgress: progress.add,
        ),
      );

      expect(zone.strayError, isNotNull,
          reason: 'pdfx fires an un-awaited support check on desktop hosts');
      expect(outputs, hasLength(3));
      expect(progress, [1 / 3, 2 / 3, 1.0]);
      for (var i = 0; i < outputs.length; i++) {
        final file = File(outputs[i]);
        expect(await file.exists(), isTrue);
        expect(outputs[i], contains('pages_page_${i + 1}.jpg'));
        final bytes = await file.readAsBytes();
        expect(bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
        final decoded = img.decodeImage(bytes)!;
        expect(decoded.width, 612, reason: 'dpi 72 == scale 1.0');
        expect(decoded.height, 792);
      }
    });

    test('honours a dpi scale', () async {
      final zone = PdfxZone();
      final input = await writePdf(tempDir, 'dpi_src.pdf', pages: 1);
      installPdfxMock(pageCount: 1);

      final outputs = await zone.guard(
        () => PdfService.instance.convertPdfToImages(
          inputPath: input,
          format: 'png',
          outputBaseName: 'scaled',
          dpi: 144,
        ),
      );

      final decoded = img.decodeImage(await File(outputs.single).readAsBytes())!;
      expect(decoded.width, 1224, reason: '612pt at 144dpi = 2x');
      expect(decoded.height, 1584);
    });

    test('drops page numbers outside the document', () async {
      final zone = PdfxZone();
      final input = await writePdf(tempDir, 'subset_src.pdf', pages: 4);
      installPdfxMock(pageCount: 4);

      final outputs = await zone.guard(
        () => PdfService.instance.convertPdfToImages(
          inputPath: input,
          format: 'png',
          outputBaseName: 'subset',
          pageNumbers: const [2, 99],
        ),
      );

      expect(outputs, hasLength(1));
      expect(outputs.single, contains('subset_page_2.png'));
    });

    test('fails with MissingPluginException when no renderer is installed',
        () async {
      final zone = PdfxZone();
      final input = await writePdf(tempDir, 'no_renderer.pdf', pages: 1);

      await expectLater(
        zone.guard(
          () => PdfService.instance.convertPdfToImages(
            inputPath: input,
            format: 'jpg',
            outputBaseName: 'nope',
          ),
        ),
        throwsA(isA<MissingPluginException>()),
      );
      expect(zone.strayError, isNotNull);
    });
  });
}
