import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

class PdfOcrService {
  PdfOcrService._();

  static final instance = PdfOcrService._();

  static const _defaultDpi = 200;

  /// Converts a PDF to plain text using ML Kit OCR.
  /// Returns the path to the generated .txt file.
  Future<String> convertToText({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final buffer = StringBuffer();
    final nativePages = await _extractNativeTextPages(inputPath);
    if (_hasUsableNativeText(nativePages)) {
      for (int i = 0; i < nativePages.length; i++) {
        if (i > 0) buffer.writeln();
        buffer.writeln('--- Page ${i + 1} ---');
        buffer.writeln(nativePages[i].trim());
        onProgress?.call((i + 1) / nativePages.length);
      }
    } else {
      List<RecognizedText> pages = [];
      try {
        pages = await _ocrAllPages(
          inputPath: inputPath,
          dpi: _defaultDpi,
          onProgress: onProgress,
        );
      } catch (_) {
        if (nativePages.isNotEmpty) {
          for (int i = 0; i < nativePages.length; i++) {
            if (i > 0) buffer.writeln();
            buffer.writeln('--- Page ${i + 1} ---');
            buffer.writeln(nativePages[i].trim());
          }
        }
      }
      for (int i = 0; i < pages.length; i++) {
        if (i > 0) buffer.writeln();
        buffer.writeln('--- Page ${i + 1} ---');
        buffer.writeln(pages[i].text.trim());
      }
    }

    await File(outputPath).writeAsString(buffer.toString());
    return outputPath;
  }

  /// Converts a PDF to DOCX using ML Kit OCR with formatting.
  /// Attempts to preserve tables by analyzing text block bounding boxes.
  /// Returns the path to the generated .docx file.
  Future<String> convertToDocx({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final nativePages = await _extractNativeTextPages(inputPath);
    String documentXml;
    if (_hasUsableNativeText(nativePages)) {
      // Embedded PDF text retains its original Unicode code points. In
      // particular, this avoids asking the Latin-only mobile OCR recognizer
      // to guess Devanagari or other non-Latin scripts.
      documentXml = _buildDocxDocumentFromText(nativePages);
      for (int i = 0; i < nativePages.length; i++) {
        onProgress?.call((i + 1) / nativePages.length);
      }
    } else {
      List<RecognizedText> pages = [];
      try {
        pages = await _ocrAllPages(
          inputPath: inputPath,
          dpi: _defaultDpi,
          onProgress: onProgress,
        );
        documentXml = _buildDocxDocument(pages);
      } catch (_) {
        documentXml = nativePages.isNotEmpty
            ? _buildDocxDocumentFromText(nativePages)
            : _buildDocxDocument(pages);
      }
    }

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

  /// OCR all pages of a PDF using ML Kit.
  /// Runs the Latin recognizer first and retries sparse pages with the
  /// Devanagari recognizer, keeping the richer result per page. This keeps
  /// Latin documents fast while fixing scanned Devanagari documents that the
  /// Latin-only model mistranscribes.
  Future<List<RecognizedText>> _ocrAllPages({
    required String inputPath,
    int dpi = _defaultDpi,
    void Function(double progress)? onProgress,
  }) async {
    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final pageCount = pdfDoc.pagesCount;
    final results = <RecognizedText>[];
    final scale = dpi / 72.0;
    final tempDir = await getTemporaryDirectory();

    TextRecognizer? latin;
    TextRecognizer? devanagari;
    TextRecognizer? chinese;

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
      for (int i = 1; i <= pageCount; i++) {
        pdfx.PdfPage? page;
        pdfx.PdfPageImage? pageImage;
        try {
          page = await pdfDoc.getPage(i);
          pageImage = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
        } catch (_) {} finally {
          try {
            await page?.close();
          } catch (_) {}
        }

        if (pageImage != null) {
          final tempFile = File(path.join(tempDir.path, 'ocr_page_$i.png'));
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

          // Retry with specialized non-Latin models when Latin OCR is sparse or non-Latin script detected
          final hasDevanagari = _containsDevanagari(best.text);
          final hasChinese = _containsChinese(best.text);

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
                final chineseResult = await chinese.processImage(inputImage);
                final chLen = _recognizedLength(chineseResult.text);
                if (chLen > bestLen ||
                    (_containsChinese(chineseResult.text) && chLen >= 3)) {
                  best = chineseResult;
                  bestLen = chLen;
                }
              }
            } catch (_) {}
          }

          results.add(best);

          try {
            await tempFile.delete();
          } catch (_) {}
        } else {
          results.add(RecognizedText(text: '', blocks: []));
        }

        onProgress?.call(i / pageCount);
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
        await pdfDoc.close();
      } catch (_) {}
    }
    return results;
  }

  int _recognizedLength(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').runes.length;

  bool _containsDevanagari(String text) => RegExp(
        r'[\u0900-\u097F]',
      ).hasMatch(text);

  bool _containsChinese(String text) => RegExp(
        r'[\u4E00-\u9FFF]',
      ).hasMatch(text);

  bool _containsArabic(String text) => RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
      ).hasMatch(text);

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

  bool _hasUsableNativeText(List<String> pages) {
    final nonWhitespace = pages.join().replaceAll(RegExp(r'\s+'), '');
    return nonWhitespace.runes.length >= 4;
  }

  /// Builds the word/document.xml content from OCR results.
  String _buildDocxDocument(List<RecognizedText> pages) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    buf.writeln('<w:body>');

    for (int pageIdx = 0; pageIdx < pages.length; pageIdx++) {
      _writePageHeading(buf, pageIdx + 1);

      final blocks = pages[pageIdx].blocks;
      if (blocks.isEmpty) {
        _writeParagraph(buf, '[No text detected on this page]');
        continue;
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

    buf.writeln('</w:body>');
    buf.writeln('</w:document>');
    return buf.toString();
  }

  String _buildDocxDocumentFromText(List<String> pages) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    buf.writeln('<w:body>');
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      _writePageHeading(buf, pageIndex + 1);
      // Digital PDFs lose table structure when flattened to paragraphs.
      // Re-infer whitespace-aligned columns so tables survive conversion.
      final lines = pages[pageIndex]
          .split(RegExp(r'\r?\n'))
          .map((l) => l.replaceAll('\t', '    '))
          .toList();
      var i = 0;
      while (i < lines.length) {
        if (lines[i].trim().isEmpty) {
          i++;
          continue;
        }
        final run = _collectTableRun(lines, i);
        if (run != null) {
          _writeStringTable(buf, run);
          i += run.length;
        } else {
          _writeParagraph(buf, lines[i].trim());
          i++;
        }
      }
    }
    buf.writeln('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>');
    buf.writeln('</w:body>');
    buf.writeln('</w:document>');
    return buf.toString();
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
