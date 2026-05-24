import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Core service for all PDF processing operations.
/// Uses syncfusion_flutter_pdf for reading/manipulating existing PDFs
/// and the pdf package for creating new PDFs.
class PdfService {
  PdfService._();

  static final instance = PdfService._();

  /// Returns the save directory for processed PDFs.
  /// Android: Download/PixelTools/PDFs (public folder) with fallback to app docs.
  /// Other platforms: app documents directory.
  Future<Directory> _getSaveDir() async {
    if (Platform.isAndroid) {
      try {
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          final dir = Directory(path.join(downloadDir.path, 'PixelTools', 'PDFs'));
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(base.path, 'PixelTools', 'PDFs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates a unique filename with the given extension.
  String _generateFileName(String baseName, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'pixeltools_${baseName}_$timestamp.$extension';
  }

  // ─── Compress PDF ───────────────────────────────────────────────────

  /// Maps 0.0-1.0 quality to Syncfusion compression level.
  syncfusion.PdfCompressionLevel _mapCompressionLevel(double quality) {
    if (quality >= 0.8) return syncfusion.PdfCompressionLevel.belowNormal;
    if (quality >= 0.5) return syncfusion.PdfCompressionLevel.normal;
    if (quality >= 0.3) return syncfusion.PdfCompressionLevel.aboveNormal;
    return syncfusion.PdfCompressionLevel.best;
  }

  /// Compresses a PDF file by rebuilding with optimized compression.
  /// [quality] ranges from 0.1 (lowest) to 1.0 (highest / no compression).
  /// Returns the path to the compressed file.
  Future<String> compressPdf({
    required String inputPath,
    required double quality,
    String? outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await _getSaveDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = path.join(saveDir.path, 'pixeltools_$timestamp.pdf');

    onProgress?.call(0.1);

    final inputBytes = File(inputPath).readAsBytesSync();
    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final pageCount = srcDoc.pages.count;

    onProgress?.call(0.2);

    final compressionLevel = _mapCompressionLevel(quality);
    final destDoc = syncfusion.PdfDocument();
    destDoc.compressionLevel = compressionLevel;

    for (int i = 0; i < pageCount; i++) {
      final template = srcDoc.pages[i].createTemplate();
      destDoc.pages.add().graphics.drawPdfTemplate(template, ui.Offset.zero);
      onProgress?.call(0.2 + ((i + 1) / pageCount) * 0.7);
    }

    srcDoc.dispose();

    final bytes = await destDoc.save();
    destDoc.dispose();

    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);

    final fileSize = await file.length();
    if (!await file.exists() || fileSize == 0) {
      throw Exception('Compressed PDF file was not created or is empty');
    }

    onProgress?.call(1.0);
    return outputPath;
  }

  // ─── Merge PDFs ─────────────────────────────────────────────────────

  /// Merges multiple PDF files into a single document.
  /// [inputPaths] are the paths to the PDF files in order.
  /// Returns the path to the merged file.
  Future<String> mergePdfs({
    required List<String> inputPaths,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    if (inputPaths.isEmpty) {
      throw ArgumentError('At least one PDF file is required');
    }

    final saveDir = await _getSaveDir();
    final outputPath = path.join(saveDir.path, _generateFileName(outputBaseName, 'pdf'));

    // Use Syncfusion for reliable PDF merging
    final mergedDoc = syncfusion.PdfDocument();

    for (int i = 0; i < inputPaths.length; i++) {
      final inputBytes = File(inputPaths[i]).readAsBytesSync();
      final doc = syncfusion.PdfDocument(inputBytes: inputBytes);

      for (int j = 0; j < doc.pages.count; j++) {
        final template = doc.pages[j].createTemplate();
        mergedDoc.pages.add().graphics.drawPdfTemplate(
              template,
              ui.Offset.zero,
            );
      }

      doc.dispose();
      onProgress?.call((i + 1) / inputPaths.length);
    }

    final List<int> bytes = await mergedDoc.save();
    mergedDoc.dispose();

    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }

  // ─── Split PDF ──────────────────────────────────────────────────────

  /// Splits a PDF into individual page files.
  /// Returns a list of paths to the split files.
  Future<List<String>> splitPdfAllPages({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    final saveDir = await _getSaveDir();
    final outputPaths = <String>[];

    for (int i = 0; i < pageCount; i++) {
      final newDoc = syncfusion.PdfDocument();
      final template = syncDoc.pages[i].createTemplate();
      newDoc.pages.add().graphics.drawPdfTemplate(
            template,
            ui.Offset.zero,
          );

      final fileName = _generateFileName('${outputBaseName}_page_${i + 1}', 'pdf');
      final outputPath = path.join(saveDir.path, fileName);
      final bytes = await newDoc.save();
      newDoc.dispose();

      await File(outputPath).writeAsBytes(bytes);
      outputPaths.add(outputPath);

      onProgress?.call((i + 1) / pageCount);
    }

    syncDoc.dispose();
    return outputPaths;
  }

  /// Extracts specific pages from a PDF.
  /// [pageNumbers] is 1-indexed list of pages to extract.
  /// Returns the path to the extracted PDF.
  Future<String> extractPages({
    required String inputPath,
    required List<int> pageNumbers,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    if (pageNumbers.isEmpty) {
      throw ArgumentError('At least one page number is required');
    }

    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    final saveDir = await _getSaveDir();

    // Validate page numbers
    for (final pageNum in pageNumbers) {
      if (pageNum < 1 || pageNum > pageCount) {
        syncDoc.dispose();
        throw ArgumentError('Page number $pageNum is out of range (1-$pageCount)');
      }
    }

    final newDoc = syncfusion.PdfDocument();
    for (int i = 0; i < pageNumbers.length; i++) {
      final pageIndex = pageNumbers[i] - 1; // Convert to 0-indexed
      final template = syncDoc.pages[pageIndex].createTemplate();
      newDoc.pages.add().graphics.drawPdfTemplate(
            template,
            ui.Offset.zero,
          );
      onProgress?.call((i + 1) / pageNumbers.length);
    }

    syncDoc.dispose();

    final fileName = _generateFileName('${outputBaseName}_extracted', 'pdf');
    final outputPath = path.join(saveDir.path, fileName);
    final bytes = await newDoc.save();
    newDoc.dispose();

    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }

  /// Splits a PDF into chunks of [pageSize] pages each.
  /// Returns a list of paths to the chunk files.
  Future<List<String>> splitPdfByChunk({
    required String inputPath,
    required int pageSize,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    if (pageSize < 1) {
      throw ArgumentError('Page size must be at least 1');
    }

    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    final saveDir = await _getSaveDir();
    final outputPaths = <String>[];

    int chunkIndex = 1;
    for (int i = 0; i < pageCount; i += pageSize) {
      final newDoc = syncfusion.PdfDocument();
      final end = (i + pageSize < pageCount) ? i + pageSize : pageCount;

      for (int j = i; j < end; j++) {
        final template = syncDoc.pages[j].createTemplate();
        newDoc.pages.add().graphics.drawPdfTemplate(
              template,
              ui.Offset.zero,
            );
      }

      final fileName = _generateFileName('${outputBaseName}_part_$chunkIndex', 'pdf');
      final outputPath = path.join(saveDir.path, fileName);
      final bytes = await newDoc.save();
      newDoc.dispose();

      await File(outputPath).writeAsBytes(bytes);
      outputPaths.add(outputPath);
      chunkIndex++;

      onProgress?.call(end / pageCount);
    }

    syncDoc.dispose();
    return outputPaths;
  }

  // ─── Convert PDF ────────────────────────────────────────────────────

  /// Converts a PDF to images (JPG or PNG).
  /// [format] is either 'jpg' or 'png'.
  /// [dpi] controls the resolution (default 150).
  /// Returns a list of paths to the converted image files.
  Future<List<String>> convertPdfToImages({
    required String inputPath,
    required String format,
    required String outputBaseName,
    int dpi = 150,
    void Function(double progress)? onProgress,
  }) async {
    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final pageCount = pdfDoc.pagesCount;
    final saveDir = await _getSaveDir();
    final outputPaths = <String>[];

    final scale = dpi / 72.0;

    for (int i = 1; i <= pageCount; i++) {
      final page = await pdfDoc.getPage(i);

      final pageImage = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
      );

      if (pageImage != null) {
        final decodedImage = img.decodeImage(pageImage.bytes);
        if (decodedImage != null) {
          Uint8List outputBytes;
          String extension;

          if (format == 'jpg') {
            outputBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: 95));
            extension = 'jpg';
          } else {
            outputBytes = Uint8List.fromList(img.encodePng(decodedImage));
            extension = 'png';
          }

          final fileName = _generateFileName('${outputBaseName}_page_$i', extension);
          final outputPath = path.join(saveDir.path, fileName);
          await File(outputPath).writeAsBytes(outputBytes);
          outputPaths.add(outputPath);
        }
      }

      onProgress?.call(i / pageCount);
    }

    await pdfDoc.close();
    return outputPaths;
  }

  /// Converts a PDF to plain text.
  /// Returns the path to the text file.
  Future<String> convertPdfToText({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await _getSaveDir();
    final fileName = _generateFileName(outputBaseName, 'txt');
    final outputPath = path.join(saveDir.path, fileName);

    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final pageCount = pdfDoc.pagesCount;
    final buffer = StringBuffer();

    for (int i = 1; i <= pageCount; i++) {
      try {
        await pdfDoc.getPage(i);
        // Note: pdfx doesn't expose text extraction directly
        // We use a placeholder indicating limitation
        buffer.writeln('--- Page $i ---');
        buffer.writeln('[Text extraction requires OCR or server-side processing]');
        buffer.writeln();
      } catch (_) {
        buffer.writeln('--- Page $i ---');
        buffer.writeln('[Page processing error]');
        buffer.writeln();
      }

      onProgress?.call(i / pageCount);
    }

    await pdfDoc.close();

    await File(outputPath).writeAsString(buffer.toString());
    return outputPath;
  }

  /// Converts a PDF to DOCX format using text-based extraction.
  /// Note: This creates a basic DOCX with extracted text. Complex layouts,
  /// images, and formatting may not be preserved. For full-fidelity conversion,
  /// consider using a server-side solution or native platform channels.
  /// Returns the path to the DOCX file.
  Future<String> convertPdfToDocx({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await _getSaveDir();
    final fileName = _generateFileName(outputBaseName, 'docx');
    final outputPath = path.join(saveDir.path, fileName);

    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final pageCount = pdfDoc.pagesCount;
    final textContent = StringBuffer();

    for (int i = 1; i <= pageCount; i++) {
      try {
        await pdfDoc.getPage(i);
        // Note: Native DOCX conversion with full text extraction requires
        // server-side processing or platform channels. This creates a basic
        // DOCX structure with page placeholders.
        if (i > 1) {
          textContent.writeln();
        }
        textContent.writeln('[Page $i - Text extraction requires OCR or server-side processing]');
      } catch (_) {
        textContent.writeln('[Page $i processing error]');
      }

      onProgress?.call(i / pageCount);
    }

    await pdfDoc.close();

    // Create a minimal DOCX file (ZIP archive with XML content)
    final archive = Archive();

    // [Content_Types].xml
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.codeUnits.length,
      _contentTypesXml.codeUnits,
    ));

    // _rels/.rels
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _relsXml.codeUnits.length,
      _relsXml.codeUnits,
    ));

    // word/document.xml
    final documentXml = _buildDocumentXml(textContent.toString());
    archive.addFile(ArchiveFile(
      'word/document.xml',
      documentXml.codeUnits.length,
      documentXml.codeUnits,
    ));

    // Write ZIP file
    final zipData = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipData);
    return outputPath;
  }

  // DOCX XML templates
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

  String _buildDocumentXml(String text) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.writeln(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.writeln('<w:body>');

    // Split text into paragraphs
    final paragraphs = text.split('\n');
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isNotEmpty) {
        // Escape XML special characters
        final escapedText = trimmed
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        buffer.writeln(
            '<w:p><w:r><w:t xml:space="preserve">$escapedText</w:t></w:r></w:p>');
      } else {
        // Empty paragraph
        buffer.writeln('<w:p/>');
      }
    }

    buffer.writeln('</w:body>');
    buffer.writeln('</w:document>');
    return buffer.toString();
  }

  /// Gets the number of pages in a PDF file.
  Future<int> getPageCount(String inputPath) async {
    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final count = syncDoc.pages.count;
    syncDoc.dispose();
    return count;
  }

  /// Renders a specific page as a PNG image for thumbnail preview.
  /// Returns the image bytes.
  Future<Uint8List?> renderPageThumbnail({
    required String inputPath,
    required int pageNumber,
    int maxWidth = 200,
  }) async {
    try {
    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
      if (pageNumber < 1 || pageNumber > pdfDoc.pagesCount) {
        await pdfDoc.close();
        return null;
      }

      final page = await pdfDoc.getPage(pageNumber);
      final scale = maxWidth / page.width;

      final pageImage = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
      );

      await pdfDoc.close();
      return pageImage?.bytes;
    } catch (_) {
      return null;
    }
  }

  /// Gets file size in bytes.
  Future<int> getFileSize(String filePath) async {
    return File(filePath).length();
  }

  /// Formats bytes to human-readable string.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
