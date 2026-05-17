import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Core service for all PDF processing operations.
/// Uses syncfusion_flutter_pdf for reading/manipulating existing PDFs
/// and the pdf package for creating new PDFs.
class PdfService {
  PdfService._();

  static final instance = PdfService._();

  /// Returns the app-specific directory for saving processed PDFs.
  Future<Directory> _getSaveDir() async {
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
    return '${baseName}_$timestamp.$extension';
  }

  // ─── Compress PDF ───────────────────────────────────────────────────

  /// Compresses a PDF file by re-rendering with reduced image quality.
  /// [quality] ranges from 0.1 (lowest) to 1.0 (highest).
  /// Returns the path to the compressed file.
  Future<String> compressPdf({
    required String inputPath,
    required double quality,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await _getSaveDir();
    final outputPath = path.join(saveDir.path, _generateFileName(outputBaseName, 'pdf'));

    onProgress?.call(0.1);

    // Load the PDF using Syncfusion for page count and metadata
    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    syncDoc.dispose();

    onProgress?.call(0.2);

    // Use pdfx to render each page as an image, then rebuild with lower quality
    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final newPdf = pw.Document();

    for (int i = 1; i <= pdfDoc.pagesCount; i++) {
      final page = await pdfDoc.getPage(i);
      final pageImage = await page.render(
        width: page.width,
        height: page.height,
        format: pdfx.PdfPageImageFormat.png,
      );

      if (pageImage != null) {
        final decodedImage = img.decodeImage(pageImage.bytes);
        if (decodedImage != null) {
          // Apply JPEG compression at the specified quality level
          final jpegBytes = img.encodeJpg(decodedImage, quality: (quality * 100).round());

          newPdf.addPage(
            pw.Page(
              pageFormat: pdf.PdfPageFormat(
                page.width,
                page.height,
              ),
              build: (context) {
                return pw.Image(
                  pw.MemoryImage(Uint8List.fromList(jpegBytes)),
                  fit: pw.BoxFit.contain,
                );
              },
            ),
          );
        }
      }

      onProgress?.call(0.2 + (i / pageCount) * 0.7);
    }

    await pdfDoc.close();

    final pdfBytes = await newPdf.save();
    await File(outputPath).writeAsBytes(pdfBytes);

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

    final syncDoc = syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    final buffer = StringBuffer();

    for (int i = 0; i < pageCount; i++) {
      final page = syncDoc.pages[i];

      // Extract text using Syncfusion's text extraction
      try {
        final text = (page as dynamic).extractText(true) as String?;
        if (text != null && text.isNotEmpty) {
          buffer.writeln('--- Page ${i + 1} ---');
          buffer.writeln(text);
          buffer.writeln();
        }
      } catch (_) {
        // Text extraction not available in this version
      }

      onProgress?.call((i + 1) / pageCount);
    }

    syncDoc.dispose();

    await File(outputPath).writeAsString(buffer.toString());
    return outputPath;
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
