import 'dart:io';
import 'dart:math';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

class PdfOcrService {
  PdfOcrService._();

  static final instance = PdfOcrService._();

  static const _defaultDpi = 200;

  /// Converts a PDF to plain text using a hybrid approach:
  /// uses native PDF text layer for digital pages and ML Kit OCR for scanned
  /// image pages or pages with only sparse watermarks/stamps.
  /// Returns the path to the generated .txt file.
  Future<String> convertToText({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final pages = await _extractPagesHybrid(
      inputPath: inputPath,
      onProgress: onProgress,
    );

    final buffer = StringBuffer();
    for (int i = 0; i < pages.length; i++) {
      if (i > 0) buffer.writeln();
      buffer.writeln('--- Page ${i + 1} ---');
      buffer.writeln(pages[i].text.trim());
    }

    await File(outputPath).writeAsString(buffer.toString());
    return outputPath;
  }

  /// Converts a PDF to DOCX using a hybrid approach:
  /// Preserves tables and formatting from both native text layouts and ML Kit
  /// OCR bounding box structures.
  /// Returns the path to the generated .docx file.
  Future<String> convertToDocx({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final pages = await _extractPagesHybrid(
      inputPath: inputPath,
      onProgress: onProgress,
    );

    final documentXml = _buildDocxDocument(pages);

    final archive = Archive();
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.codeUnits.length,
      _contentTypesXml.codeUnits,
    ));
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _relsXml.codeUnits.length,
      _relsXml.codeUnits,
    ));
    archive.addFile(ArchiveFile(
      'word/_rels/document.xml.rels',
      _documentRelsXml.codeUnits.length,
      _documentRelsXml.codeUnits,
    ));
    archive.addFile(ArchiveFile(
      'word/styles.xml',
      _stylesXml.codeUnits.length,
      _stylesXml.codeUnits,
    ));
    archive.addFile(ArchiveFile(
      'word/document.xml',
      documentXml.codeUnits.length,
      documentXml.codeUnits,
    ));

    final zipData = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipData);
    return outputPath;
  }

  /// Evaluates each page individually:
  /// - If a page has substantial native text (>= 200 non-whitespace chars), uses native text directly.
  /// - If a page has missing or sparse native text (< 200 chars, e.g. scanned image or scanner watermark),
  ///   renders the page and runs ML Kit OCR.
  /// - If OCR yields significantly more content than the sparse native stamp, adopts OCR.
  Future<List<_PageData>> _extractPagesHybrid({
    required String inputPath,
    void Function(double progress)? onProgress,
  }) async {
    final nativePages = await _extractNativeTextPages(inputPath);
    pdfx.PdfDocument? pdfDoc;
    try {
      if (await pdfx.hasPdfSupport()) {
        pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
      }
    } catch (_) {}

    final pageCount = pdfDoc?.pagesCount ?? nativePages.length;
    if (pageCount == 0) {
      try {
        await pdfDoc?.close();
      } catch (_) {}
      return const [];
    }

    Directory? tempDir;
    Future<Directory> getSafeTempDir() async {
      if (tempDir != null) return tempDir!;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (_) {
        tempDir = Directory.systemTemp;
      }
      return tempDir!;
    }

    final results = <_PageData>[];

    TextRecognizer? latin;
    TextRecognizer? devanagari;
    TextRecognizer? chinese;
    TextRecognizer? japanese;
    TextRecognizer? korean;

    bool recognizersInitialized = false;
    void ensureRecognizers() {
      if (recognizersInitialized) return;
      recognizersInitialized = true;
      try {
        latin = TextRecognizer(script: TextRecognitionScript.latin);
      } catch (_) {}
      try {
        devanagari = TextRecognizer(script: TextRecognitionScript.devanagiri);
      } catch (_) {}
      try {
        chinese = TextRecognizer(script: TextRecognitionScript.chinese);
      } catch (_) {}
      try {
        japanese = TextRecognizer(script: TextRecognitionScript.japanese);
      } catch (_) {}
      try {
        korean = TextRecognizer(script: TextRecognitionScript.korean);
      } catch (_) {}
    }

    try {
      for (int i = 0; i < pageCount; i++) {
        final nativeText =
            (i < nativePages.length) ? nativePages[i].trim() : '';
        final nativeChars = _recognizedLength(nativeText);

        // Dense digital text (>= 200 non-whitespace characters) is 100% faithful
        // and skips rendering/OCR overhead.
        if (nativeChars >= 200 || pdfDoc == null) {
          results.add(_PageData(
            pageIndex: i,
            text: nativeText,
            isOcr: false,
          ));
          onProgress?.call((i + 1) / pageCount);
          continue;
        }

        // For pages with sparse, watermark-only, or empty native text (< 200 chars),
        // render safely and run ML Kit OCR.
        ensureRecognizers();
        final safeTemp = await getSafeTempDir();
        pdfx.PdfPage? page;
        RecognizedText? ocrResult;
        try {
          page = await pdfDoc.getPage(i + 1);
          ocrResult = await _ocrPage(
            page: page,
            pageIndex: i + 1,
            tempDir: safeTemp,
            latin: latin,
            devanagari: devanagari,
            chinese: chinese,
            japanese: japanese,
            korean: korean,
          );
        } catch (_) {} finally {
          try {
            await page?.close();
          } catch (_) {}
        }

        final ocrText = ocrResult?.text.trim() ?? '';
        final ocrChars = _recognizedLength(ocrText);

        final bool useOcr = ocrResult != null &&
            ocrChars > 0 &&
            (nativeChars == 0 ||
                (ocrChars > (nativeChars * 1.3).round() &&
                    (ocrChars - nativeChars) >= 15));

        if (useOcr) {
          results.add(_PageData(
            pageIndex: i,
            text: ocrText,
            ocrResult: ocrResult,
            isOcr: true,
          ));
        } else {
          results.add(_PageData(
            pageIndex: i,
            text: nativeText,
            isOcr: false,
          ));
        }

        onProgress?.call((i + 1) / pageCount);
      }
    } finally {
      try {
        await latin?.close();
      } catch (_) {}
      try {
        await devanagari?.close();
      } catch (_) {}
      try {
        await chinese?.close();
      } catch (_) {}
      try {
        await japanese?.close();
      } catch (_) {}
      try {
        await korean?.close();
      } catch (_) {}
      try {
        await pdfDoc?.close();
      } catch (_) {}
    }

    return results;
  }

  /// Calculates safe render dimensions clamped to avoid mobile OOM on high-res scans or image PDFs.
  static (double, double) _calculateRenderDimensions(
    double pageWidth,
    double pageHeight,
    int dpi,
  ) {
    if (pageWidth <= 0 || pageHeight <= 0) {
      return (1200.0, 1600.0);
    }

    final scale = dpi / 72.0;
    var targetW = pageWidth * scale;
    var targetH = pageHeight * scale;

    final longest = max(targetW, targetH);
    const double maxDimension = 2048.0;
    const double minLongest = 1200.0;

    if (longest > maxDimension) {
      final factor = maxDimension / longest;
      targetW = (targetW * factor).roundToDouble();
      targetH = (targetH * factor).roundToDouble();
    } else if (longest < minLongest && longest > 0) {
      final factor = minLongest / longest;
      targetW = (targetW * factor).roundToDouble();
      targetH = (targetH * factor).roundToDouble();
    }

    return (targetW, targetH);
  }

  /// Renders a PDF page safely using JPEG for fast compression and memory efficiency,
  /// with automated fallback to lower resolutions if memory is constrained.
  Future<pdfx.PdfPageImage?> _renderPageSafely(
    pdfx.PdfPage page,
    double width,
    double height,
  ) async {
    try {
      return await page.render(
        width: width,
        height: height,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 90,
      );
    } catch (_) {
      try {
        return await page.render(
          width: (width * 0.6).roundToDouble(),
          height: (height * 0.6).roundToDouble(),
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 85,
        );
      } catch (_) {
        try {
          final scaleDown = 1000.0 / max(page.width, page.height);
          return await page.render(
            width: (page.width * scaleDown).roundToDouble(),
            height: (page.height * scaleDown).roundToDouble(),
            format: pdfx.PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
        } catch (_) {
          return null;
        }
      }
    }
  }

  /// OCR a single page of a PDF using ML Kit with multi-language script fallbacks.
  Future<RecognizedText> _ocrPage({
    required pdfx.PdfPage page,
    required int pageIndex,
    required Directory tempDir,
    required TextRecognizer? latin,
    required TextRecognizer? devanagari,
    required TextRecognizer? chinese,
    required TextRecognizer? japanese,
    required TextRecognizer? korean,
    int dpi = _defaultDpi,
  }) async {
    final (renderW, renderH) = _calculateRenderDimensions(
      page.width,
      page.height,
      dpi,
    );

    final pageImage = await _renderPageSafely(page, renderW, renderH);
    if (pageImage == null) {
      return RecognizedText(text: '', blocks: []);
    }

    final tempFile = File(
      path.join(
        tempDir.path,
        'ocr_page_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.jpg',
      ),
    );

    try {
      await tempFile.writeAsBytes(pageImage.bytes);
      final inputImage = InputImage.fromFile(tempFile);

      RecognizedText? latinResult;
      try {
        if (latin != null) {
          latinResult = await latin.processImage(inputImage);
        }
      } catch (_) {}

      var best = latinResult ?? RecognizedText(text: '', blocks: []);
      var bestLen = _recognizedLength(best.text);

      final hasDevanagari = _containsDevanagari(best.text);
      final hasChinese = _containsChinese(best.text);
      final hasJapanese = _containsJapanese(best.text);
      final hasKorean = _containsKorean(best.text);

      if (bestLen < 25 || hasDevanagari) {
        try {
          if (devanagari != null) {
            final devResult = await devanagari.processImage(inputImage);
            final devLen = _recognizedLength(devResult.text);
            if (devLen > bestLen ||
                (_containsDevanagari(devResult.text) && devLen >= 3)) {
              best = devResult;
              bestLen = devLen;
            }
          }
        } catch (_) {}
      }

      if (bestLen < 25 || hasChinese) {
        try {
          if (chinese != null) {
            final chResult = await chinese.processImage(inputImage);
            final chLen = _recognizedLength(chResult.text);
            if (chLen > bestLen ||
                (_containsChinese(chResult.text) && chLen >= 3)) {
              best = chResult;
              bestLen = chLen;
            }
          }
        } catch (_) {}
      }

      if (bestLen < 25 || hasJapanese) {
        try {
          if (japanese != null) {
            final jaResult = await japanese.processImage(inputImage);
            final jaLen = _recognizedLength(jaResult.text);
            if (jaLen > bestLen ||
                (_containsJapanese(jaResult.text) && jaLen >= 3)) {
              best = jaResult;
              bestLen = jaLen;
            }
          }
        } catch (_) {}
      }

      if (bestLen < 25 || hasKorean) {
        try {
          if (korean != null) {
            final koResult = await korean.processImage(inputImage);
            final koLen = _recognizedLength(koResult.text);
            if (koLen > bestLen ||
                (_containsKorean(koResult.text) && koLen >= 3)) {
              best = koResult;
              bestLen = koLen;
            }
          }
        } catch (_) {}
      }

      return best;
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  int _recognizedLength(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').runes.length;

  bool _containsDevanagari(String text) => RegExp(
        r'[\u0900-\u097F]',
      ).hasMatch(text);

  bool _containsChinese(String text) => RegExp(
        r'[\u4E00-\u9FFF]',
      ).hasMatch(text);

  bool _containsJapanese(String text) => RegExp(
        r'[\u3040-\u309F\u30A0-\u30FF]',
      ).hasMatch(text);

  bool _containsKorean(String text) => RegExp(
        r'[\uAC00-\uD7AF\u1100-\u11FF]',
      ).hasMatch(text);

  bool _containsArabic(String text) => RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
      ).hasMatch(text);

  @visibleForTesting
  static (double, double) calculateRenderDimensions(
    double pageWidth,
    double pageHeight, [
    int dpi = _defaultDpi,
  ]) =>
      _calculateRenderDimensions(pageWidth, pageHeight, dpi);

  @visibleForTesting
  static int recognizedLength(String text) =>
      instance._recognizedLength(text);

  @visibleForTesting
  static bool containsDevanagari(String text) =>
      instance._containsDevanagari(text);

  @visibleForTesting
  static bool containsChinese(String text) => instance._containsChinese(text);

  @visibleForTesting
  static bool containsJapanese(String text) => instance._containsJapanese(text);

  @visibleForTesting
  static bool containsKorean(String text) => instance._containsKorean(text);

  @visibleForTesting
  static bool containsArabic(String text) => instance._containsArabic(text);

  @visibleForTesting
  static List<String> splitColumns(String line) => instance._splitColumns(line);

  @visibleForTesting
  static List<List<String>>? collectTableRun(List<String> lines, int start) =>
      instance._collectTableRun(lines, start);

  /// Uses the PDF's text layer before falling back to OCR. This is both faster
  /// and more faithful for digital documents, where OCR would lose Unicode
  /// glyphs, reading order, and often punctuation.
  Future<List<String>> _extractNativeTextPages(String inputPath) async {
    try {
      final document = syncfusion.PdfDocument(
        inputBytes: await File(inputPath).readAsBytes(),
      );
      try {
        final extractor = syncfusion.PdfTextExtractor(document);
        return List<String>.generate(
          document.pages.count,
          (index) => extractor.extractText(
            startPageIndex: index,
            endPageIndex: index,
          ),
          growable: false,
        );
      } finally {
        document.dispose();
      }
    } catch (_) {
      return const <String>[];
    }
  }

  /// Builds the word/document.xml content supporting both OCR results and native text pages.
  String _buildDocxDocument(List<_PageData> pages) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    buf.writeln('<w:body>');

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      _writePageHeading(buf, i + 1);

      if (page.isOcr && page.ocrResult != null) {
        _writeOcrPageContent(buf, page.ocrResult!);
      } else {
        _writeNativePageContent(buf, page.text);
      }
    }

    buf.writeln('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>');
    buf.writeln('</w:body>');
    buf.writeln('</w:document>');
    return buf.toString();
  }

  void _writeOcrPageContent(StringBuffer buf, RecognizedText ocrResult) {
    final blocks = ocrResult.blocks;
    if (blocks.isEmpty) {
      final text = ocrResult.text.trim();
      if (text.isNotEmpty) {
        _writeParagraph(buf, text);
      } else {
        _writeParagraph(buf, '[No text detected on this page]');
      }
      return;
    }

    final table = _detectTables(blocks);

    if (table.isNotEmpty) {
      for (final block in blocks) {
        final inTable = table.any((row) => row.contains(block));
        if (inTable) continue;
        _writeBlockContent(buf, block);
      }
      _writeTable(buf, table);
    } else {
      for (final block in blocks) {
        _writeBlockContent(buf, block);
      }
    }
  }

  void _writeNativePageContent(StringBuffer buf, String nativeText) {
    final trimmed = nativeText.trim();
    if (trimmed.isEmpty) {
      _writeParagraph(buf, '[No text detected on this page]');
      return;
    }

    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll('\t', '    '))
        .toList();
    var i = 0;
    bool wroteAny = false;
    while (i < lines.length) {
      if (lines[i].trim().isEmpty) {
        i++;
        continue;
      }
      final run = _collectTableRun(lines, i);
      if (run != null) {
        _writeStringTable(buf, run);
        wroteAny = true;
        i += run.length;
      } else {
        _writeParagraph(buf, lines[i].trim());
        wroteAny = true;
        i++;
      }
    }
    if (!wroteAny) {
      _writeParagraph(buf, '[No text detected on this page]');
    }
  }

  /// Splits a line into columns on runs of 2+ spaces (Syncfusion preserves
  /// inter-column gaps as multiple spaces in extracted text).
  List<String> _splitColumns(String line) => line
      .split(RegExp(r'\s{2,}'))
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList(growable: false);

  /// Collects a run of >= 2 consecutive lines sharing the same column count
  /// (>= 2 columns). Returns null when line [start] does not begin a table.
  List<List<String>>? _collectTableRun(List<String> lines, int start) {
    final first = _splitColumns(lines[start]);
    if (first.length < 2) return null;
    final run = <List<String>>[first];
    var i = start + 1;
    while (i < lines.length) {
      if (lines[i].trim().isEmpty) break;
      final cols = _splitColumns(lines[i]);
      if (cols.length != first.length) break;
      run.add(cols);
      i++;
    }
    return run.length >= 2 ? run : null;
  }

  void _writeStringTable(StringBuffer buf, List<List<String>> rows) {
    buf.writeln('<w:tbl>');
    buf.writeln(
      '<w:tblPr>'
      '<w:tblW w:w="5000" w:type="pct"/>'
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '</w:tblBorders>'
      '</w:tblPr>',
    );
    for (int r = 0; r < rows.length; r++) {
      buf.writeln(
        '<w:tr><w:trPr>'
        '<w:tblHeader w:val="${r == 0 ? "1" : "0"}"/>'
        '</w:trPr>',
      );
      for (final cell in rows[r]) {
        final text = _escapeXml(cell);
        final isRtl = _containsArabic(cell);
        final rtlProp = isRtl ? '<w:rtl/>' : '';
        buf.writeln(
          '<w:tc>'
          '<w:p><w:r><w:rPr>${_fontRunProps()}$rtlProp</w:rPr>'
          '<w:t xml:space="preserve">$text</w:t></w:r></w:p>'
          '</w:tc>',
        );
      }
      buf.writeln('</w:tr>');
    }
    buf.writeln('</w:tbl>');
  }

  /// Font run keeps Latin text on Calibri while complex scripts
  /// (Devanagari, Chinese, Arabic) fall back to appropriate fonts.
  String _fontRunProps() =>
      '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="SimSun" w:cs="Arial, Noto Sans Devanagari, Noto Sans Arabic"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/>';

  void _writePageHeading(StringBuffer buf, int pageNumber) {
    buf.writeln(
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
      '<w:r><w:t>Page $pageNumber</w:t></w:r></w:p>',
    );
  }

  void _writeBlockContent(StringBuffer buf, TextBlock block) {
    if (block.lines.isEmpty) return;
    final text = block.text.trim();
    if (text.isEmpty) return;

    if (block.lines.length == 1) {
      _writeParagraph(buf, text);
    } else {
      final lines =
          block.lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty);
      for (final line in lines) {
        _writeParagraph(buf, line);
      }
    }
  }

  void _writeParagraph(StringBuffer buf, String text) {
    final escaped = _escapeXml(text);
    final isRtl = _containsArabic(text);
    final rtlProp = isRtl ? '<w:rtl/>' : '';
    final pPr = isRtl ? '<w:pPr><w:bidi/></w:pPr>' : '';
    buf.writeln(
      '<w:p>$pPr<w:r><w:rPr>${_fontRunProps()}$rtlProp</w:rPr>'
      '<w:t xml:space="preserve">$escaped</w:t></w:r></w:p>',
    );
  }

  void _writeTable(StringBuffer buf, List<List<TextBlock>> table) {
    buf.writeln('<w:tbl>');

    buf.writeln(
      '<w:tblPr>'
      '<w:tblW w:w="5000" w:type="pct"/>'
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
      '</w:tblBorders>'
      '</w:tblPr>',
    );

    for (int rowIdx = 0; rowIdx < table.length; rowIdx++) {
      final row = table[rowIdx];
      final isHeader = rowIdx == 0;
      buf.writeln(
        '<w:tr><w:trPr>'
        '<w:tblHeader w:val="${isHeader ? "1" : "0"}"/>'
        '</w:trPr>',
      );

      for (final cell in row) {
        final text = _escapeXml(cell.text.trim());
        final isRtl = _containsArabic(cell.text);
        final rtlProp = isRtl ? '<w:rtl/>' : '';
        buf.writeln(
          '<w:tc>'
          '<w:p><w:r><w:rPr>${_fontRunProps()}$rtlProp</w:rPr>'
          '<w:t xml:space="preserve">$text</w:t></w:r></w:p>'
          '</w:tc>',
        );
      }

      buf.writeln('</w:tr>');
    }

    buf.writeln('</w:tbl>');
  }

  /// Simple table detection using bounding box analysis.
  /// Groups [TextBlock]s into rows by vertical proximity,
  /// then checks for consistent column alignment across rows.
  List<List<TextBlock>> _detectTables(List<TextBlock> blocks) {
    if (blocks.length < 4) return [];

    final items = blocks.map((b) => (b, b.boundingBox)).toList();
    items.sort((a, b) => a.$1.boundingBox.top.compareTo(b.$1.boundingBox.top));

    const rowThreshold = 24.0;
    const minColumns = 2;
    const minRows = 2;

    final rows = <List<TextBlock>>[];
    for (final item in items) {
      bool added = false;
      for (final row in rows) {
        if ((item.$1.boundingBox.top - row.first.boundingBox.top).abs() <
            rowThreshold) {
          row.add(item.$1);
          added = true;
          break;
        }
      }
      if (!added) {
        rows.add([item.$1]);
      }
    }

    if (rows.length < minRows) return [];

    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }

    final colCount = rows.map((r) => r.length).reduce(min);
    if (colCount < minColumns) return [];

    final filteredRows = rows.where((r) => r.length >= colCount).toList();
    if (filteredRows.length < minRows) return [];

    const colTolerance = 30.0;
    final table = <List<TextBlock>>[];

    for (int r = 0; r < filteredRows.length; r++) {
      final row = filteredRows[r];
      final tableRow = <TextBlock>[];
      for (int c = 0; c < colCount && c < row.length; c++) {
        final colX = row[c].boundingBox.left;
        if (r == 0 ||
            (table.isNotEmpty &&
                c < table[0].length &&
                (table[0][c].boundingBox.left - colX).abs() < colTolerance)) {
          tableRow.add(row[c]);
        }
      }
      if (tableRow.length >= minColumns) {
        table.add(tableRow);
      }
    }

    return table.length >= minRows ? table : [];
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static const String _contentTypesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  static const String _relsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const String _documentRelsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const String _stylesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Noto Sans Devanagari"/>
      <w:sz w:val="22"/><w:szCs w:val="22"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:rPr>
      <w:b/><w:bCs/>
      <w:sz w:val="32"/><w:szCs w:val="32"/>
    </w:rPr>
  </w:style>
</w:styles>''';
}

class _PageData {
  final int pageIndex;
  final String text;
  final RecognizedText? ocrResult;
  final bool isOcr;

  const _PageData({
    required this.pageIndex,
    required this.text,
    this.ocrResult,
    required this.isOcr,
  });
}
