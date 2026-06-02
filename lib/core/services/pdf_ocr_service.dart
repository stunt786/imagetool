import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

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
    final pages = await _ocrAllPages(
      inputPath: inputPath,
      dpi: _defaultDpi,
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

  /// Converts a PDF to DOCX using ML Kit OCR with formatting.
  /// Attempts to preserve tables by analyzing text block bounding boxes.
  /// Returns the path to the generated .docx file.
  Future<String> convertToDocx({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    final pages = await _ocrAllPages(
      inputPath: inputPath,
      dpi: _defaultDpi,
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
      'word/document.xml',
      documentXml.codeUnits.length,
      documentXml.codeUnits,
    ));

    final zipData = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipData);
    return outputPath;
  }

  /// OCR all pages of a PDF using ML Kit.
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

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    for (int i = 1; i <= pageCount; i++) {
      final page = await pdfDoc.getPage(i);
      final pageImage = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
      );
      await page.close();

      if (pageImage != null) {
        final tempFile = File(path.join(tempDir.path, 'ocr_page_$i.png'));
        await tempFile.writeAsBytes(pageImage.bytes);

        final inputImage = InputImage.fromFile(tempFile);
        final recognizedText = await recognizer.processImage(inputImage);
        results.add(recognizedText);

        await tempFile.delete();
      } else {
        results.add(RecognizedText(text: '', blocks: []));
      }

      onProgress?.call(i / pageCount);
    }

    await recognizer.close();
    await pdfDoc.close();
    return results;
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
      final lines = block.lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty);
      for (final line in lines) {
        _writeParagraph(buf, line);
      }
    }
  }

  void _writeParagraph(StringBuffer buf, String text) {
    final escaped = _escapeXml(text);
    buf.writeln(
      '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>',
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
        buf.writeln(
          '<w:tc>'
          '<w:p><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>'
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
        if ((item.$1.boundingBox.top - row.first.boundingBox.top).abs() < rowThreshold) {
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
        if (r == 0 || (table.isNotEmpty && c < table[0].length &&
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

  static const String _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  static const String _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
}
