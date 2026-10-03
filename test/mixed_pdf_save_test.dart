import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

import 'pdf_ops_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mixed_pdf_save_test_');
    PathProviderPlatform.instance = FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('createPdfFromMixedItems merges multiple multi-page PDFs and images with all pages preserved', () async {
    // 1. Create a 3-page PDF
    final pdf1Path = await writePdf(tempDir, 'doc1.pdf', pages: 3, text: 'Doc 1 Page');

    // 2. Create a 2-page PDF
    final pdf2Path = await writePdf(tempDir, 'doc2.pdf', pages: 2, text: 'Doc 2 Page');

    // 3. Create a test PNG image (100x100 solid blue)
    final image1 = img.Image(width: 100, height: 100);
    img.fill(image1, color: img.ColorRgb8(0, 0, 255));
    final img1Path = '${tempDir.path}/img1.png';
    await File(img1Path).writeAsBytes(img.encodePng(image1));

    // 4. Create a test JPG image (200x150 solid red)
    final image2 = img.Image(width: 200, height: 150);
    img.fill(image2, color: img.ColorRgb8(255, 0, 0));
    final img2Path = '${tempDir.path}/img2.jpg';
    await File(img2Path).writeAsBytes(img.encodeJpg(image2));

    // Execute createPdfFromMixedItems with all 4 items
    final outPath = await PdfService.instance.createPdfFromMixedItems(
      paths: [pdf1Path, img1Path, pdf2Path, img2Path],
      outputBaseName: 'combined_export',
    );

    expect(File(outPath).existsSync(), isTrue);

    // Verify page count: 3 (pdf1) + 1 (img1) + 2 (pdf2) + 1 (img2) = 7 pages
    final outBytes = await File(outPath).readAsBytes();
    final doc = syncfusion.PdfDocument(inputBytes: outBytes);
    try {
      expect(doc.pages.count, equals(7));
      for (int i = 0; i < doc.pages.count; i++) {
        final size = doc.pages[i].size;
        final isA4 = (size.width - syncfusion.PdfPageSize.a4.width).abs() < 1.0 ||
            (size.width - syncfusion.PdfPageSize.a4.height).abs() < 1.0;
        expect(isA4, isTrue);
      }
    } finally {
      doc.dispose();
    }
  });

  test('createPdfFromMixedItems throws ArgumentError when no valid files are provided', () async {
    expect(
      () => PdfService.instance.createPdfFromMixedItems(
        paths: ['${tempDir.path}/non_existent.pdf', ''],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
