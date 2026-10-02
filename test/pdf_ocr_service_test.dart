import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/services/pdf_ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfOcrService render dimension calculations', () {
    test('clamps high-res scanned / camera image PDFs safely to max 2048px', () {
      // 3000 x 4000 camera scan (would previously be 8333 x 11111 px and OOM)
      final (w, h) = PdfOcrService.calculateRenderDimensions(3000, 4000);
      expect(h, equals(2048.0));
      expect(w, equals(1536.0));
      // Aspect ratio matches 3000 / 4000 = 0.75
      expect((w / h * 100).round(), equals(75));
    });

    test('clamps high-res landscape scan correctly', () {
      final (w, h) = PdfOcrService.calculateRenderDimensions(4000, 2500);
      expect(w, equals(2048.0));
      expect(h, equals(1280.0));
    });

    test('scales standard A4 PDF (595x842 pt) cleanly to optimal OCR resolution', () {
      final (w, h) = PdfOcrService.calculateRenderDimensions(595.28, 841.89);
      expect(h, equals(2048.0));
      expect(w, closeTo(1448.0, 2.0));
      expect(w, lessThanOrEqualTo(2048.0));
      expect(h, lessThanOrEqualTo(2048.0));
    });

    test('ensures small page is scaled up to at least minLongest (1200px) for OCR legibility', () {
      // Small page: 200 x 300 pt at 200 DPI base scale would be 555 x 833
      final (w, h) = PdfOcrService.calculateRenderDimensions(200, 300);
      expect(h, equals(1200.0));
      expect(w, equals(800.0));
    });

    test('returns safe fallback for invalid or zero dimensions', () {
      final (w, h) = PdfOcrService.calculateRenderDimensions(0, 0);
      expect(w, equals(1200.0));
      expect(h, equals(1600.0));
    });
  });

  group('PdfOcrService script detection', () {
    test('accurately identifies Devanagari script', () {
      expect(PdfOcrService.containsDevanagari('नमस्ते संसार'), isTrue);
      expect(PdfOcrService.containsDevanagari('काठमाडौँ नेपाल'), isTrue);
      expect(PdfOcrService.containsDevanagari('Hello World'), isFalse);
      expect(PdfOcrService.containsDevanagari('12345'), isFalse);
    });

    test('accurately identifies Chinese script', () {
      expect(PdfOcrService.containsChinese('你好世界'), isTrue);
      expect(PdfOcrService.containsChinese('文档识别'), isTrue);
      expect(PdfOcrService.containsChinese('Hello World'), isFalse);
    });

    test('accurately identifies Japanese script', () {
      expect(PdfOcrService.containsJapanese('こんにちは'), isTrue);
      expect(PdfOcrService.containsJapanese('カタカナテスト'), isTrue);
      expect(PdfOcrService.containsJapanese('English text'), isFalse);
    });

    test('accurately identifies Korean script', () {
      expect(PdfOcrService.containsKorean('안녕하세요'), isTrue);
      expect(PdfOcrService.containsKorean('테스트'), isTrue);
      expect(PdfOcrService.containsKorean('English text'), isFalse);
    });

    test('accurately identifies Arabic script', () {
      expect(PdfOcrService.containsArabic('مرحبا بالعالم'), isTrue);
      expect(PdfOcrService.containsArabic('سلام'), isTrue);
      expect(PdfOcrService.containsArabic('English text'), isFalse);
    });
  });

  group('PdfOcrService text helpers & table parsing', () {
    test('recognizedLength ignores whitespace runes', () {
      expect(PdfOcrService.recognizedLength('  H e l l o  \n\t World '), equals(10));
      expect(PdfOcrService.recognizedLength('   \n\t  '), equals(0));
    });

    test('splitColumns divides on 2 or more consecutive spaces', () {
      final cols = PdfOcrService.splitColumns('Item    Qty    Price');
      expect(cols, equals(['Item', 'Qty', 'Price']));
    });

    test('collectTableRun detects aligned table rows', () {
      final lines = [
        'Title of Document',
        '',
        'Name          Role          Dept',
        'Alice         Developer     Engineering',
        'Bob           Designer      Product',
        '',
        'Footer note',
      ];
      final run = PdfOcrService.collectTableRun(lines, 2);
      expect(run, isNotNull);
      expect(run!.length, equals(3));
      expect(run[0], equals(['Name', 'Role', 'Dept']));
      expect(run[1], equals(['Alice', 'Developer', 'Engineering']));
      expect(run[2], equals(['Bob', 'Designer', 'Product']));
    });

    test('collectTableRun returns null for single non-table lines', () {
      final lines = ['Just a single column line of text'];
      final run = PdfOcrService.collectTableRun(lines, 0);
      expect(run, isNull);
    });
  });

  group('PdfOcrService document conversion', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdf_ocr_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('converts digital PDF with text and tables to TXT and DOCX', () async {
      // Create a test PDF with Syncfusion
      final doc = syncfusion.PdfDocument();
      final page = doc.pages.add();
      final font = syncfusion.PdfStandardFont(
        syncfusion.PdfFontFamily.helvetica,
        12,
      );

      final text = 'PixelTools Hybrid Extraction Test.\n'
          'This is a multi-line paragraph verifying digital text layer preservation.\n'
          'It contains enough characters to be recognized as high-fidelity digital text.';
      page.graphics.drawString(
        text,
        font,
        bounds: const ui.Rect.fromLTWH(20, 20, 500, 200),
      );

      final pdfBytes = await doc.save();
      doc.dispose();

      final pdfFile = File('${tempDir.path}/test_digital.pdf');
      await pdfFile.writeAsBytes(pdfBytes);

      final txtFile = '${tempDir.path}/test_digital.txt';
      final docxFile = '${tempDir.path}/test_digital.docx';

      double reportedProgress = 0.0;
      await PdfOcrService.instance.convertToText(
        inputPath: pdfFile.path,
        outputPath: txtFile,
        onProgress: (p) => reportedProgress = p,
      );

      expect(reportedProgress, equals(1.0));
      expect(File(txtFile).existsSync(), isTrue);
      final txtContent = await File(txtFile).readAsString();
      expect(txtContent, contains('--- Page 1 ---'));
      expect(txtContent, contains('PixelTools Hybrid Extraction Test'));
      expect(txtContent, contains('digital text layer preservation'));

      double docxProgress = 0.0;
      await PdfOcrService.instance.convertToDocx(
        inputPath: pdfFile.path,
        outputPath: docxFile,
        onProgress: (p) => docxProgress = p,
      );

      expect(docxProgress, equals(1.0));
      expect(File(docxFile).existsSync(), isTrue);
      expect(File(docxFile).lengthSync(), greaterThan(100));
    });
  });
}
