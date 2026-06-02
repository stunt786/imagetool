import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

import 'pdf_ocr_service.dart';

/// Core service for all PDF processing operations.
/// Uses syncfusion_flutter_pdf for reading/manipulating existing PDFs
/// and the pdf package for creating new PDFs.
class PdfService {
  PdfService._();

  static final instance = PdfService._();

  /// Returns the save directory for processed PDFs.
  /// Android: Download/PixelTools/PDFs (public folder) with fallback to app docs.
  /// Other platforms: app documents directory.
  Future<Directory> getSaveDir() async {
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
  static String _generateFileName(String baseName, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'pixeltools_${baseName}_$timestamp.$extension';
  }

  // ─── Compress PDF ───────────────────────────────────────────────────

  /// Maps 0.0-1.0 quality to Syncfusion compression level.
  static syncfusion.PdfCompressionLevel _mapCompressionLevel(double quality) {
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
    final saveDir = await getSaveDir();
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

    final saveDir = await getSaveDir();
    final outputPath = path.join(saveDir.path, _generateFileName(outputBaseName, 'pdf'));

    // Use Syncfusion for reliable PDF merging
    final mergedDoc = syncfusion.PdfDocument();

    for (int i = 0; i < inputPaths.length; i++) {
      final inputBytes = File(inputPaths[i]).readAsBytesSync();
      final doc = syncfusion.PdfDocument(inputBytes: inputBytes);

      for (int j = 0; j < doc.pages.count; j++) {
        final page = doc.pages[j];
        final template = page.createTemplate();
        final pageSize = page.size;

        final section = mergedDoc.sections!.add();
        section.pageSettings.size = pageSize;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(
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
    final saveDir = await getSaveDir();
    final outputPaths = <String>[];

    for (int i = 0; i < pageCount; i++) {
      final page = syncDoc.pages[i];
      final template = page.createTemplate();
      final pageSize = page.size;

      final newDoc = syncfusion.PdfDocument();
      newDoc.pageSettings.size = pageSize;
      newDoc.pageSettings.margins.all = 0;
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
    final saveDir = await getSaveDir();

    // Validate page numbers
    for (final pageNum in pageNumbers) {
      if (pageNum < 1 || pageNum > pageCount) {
        syncDoc.dispose();
        throw ArgumentError('Page number $pageNum is out of range (1-$pageCount)');
      }
    }

    final newDoc = syncfusion.PdfDocument();
    for (int i = 0; i < pageNumbers.length; i++) {
      final pageIndex = pageNumbers[i] - 1;
      final page = syncDoc.pages[pageIndex];
      final template = page.createTemplate();
      final pageSize = page.size;

      final section = newDoc.sections!.add();
      section.pageSettings.size = pageSize;
      section.pageSettings.margins.all = 0;
      section.pages.add().graphics.drawPdfTemplate(
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
    final saveDir = await getSaveDir();
    final outputPaths = <String>[];

    int chunkIndex = 1;
    for (int i = 0; i < pageCount; i += pageSize) {
      final newDoc = syncfusion.PdfDocument();
      final end = (i + pageSize < pageCount) ? i + pageSize : pageCount;

      for (int j = i; j < end; j++) {
        final page = syncDoc.pages[j];
        final template = page.createTemplate();
        final pageSize = page.size;

        final section = newDoc.sections!.add();
        section.pageSettings.size = pageSize;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(
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
    final saveDir = await getSaveDir();
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

  /// Converts a PDF to plain text using ML Kit OCR.
  /// Returns the path to the text file.
  Future<String> convertPdfToText({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await getSaveDir();
    final fileName = _generateFileName(outputBaseName, 'txt');
    final outputPath = path.join(saveDir.path, fileName);

    return PdfOcrService.instance.convertToText(
      inputPath: inputPath,
      outputPath: outputPath,
      onProgress: onProgress,
    );
  }

  /// Converts a PDF to DOCX format using ML Kit OCR with formatting.
  /// Preserves text, paragraphs, and detected tables.
  /// Returns the path to the DOCX file.
  Future<String> convertPdfToDocx({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await getSaveDir();
    final fileName = _generateFileName(outputBaseName, 'docx');
    final outputPath = path.join(saveDir.path, fileName);

    return PdfOcrService.instance.convertToDocx(
      inputPath: inputPath,
      outputPath: outputPath,
      onProgress: onProgress,
    );
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

  // ─── Isolate Workers ─────────────────────────────────────────────────

  /// Compress worker for background isolate execution.
  /// Params: inputBytes (Uint8List), quality (double)
  static Future<Uint8List> isolateCompressWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes']));
    final quality = params['quality'] as double;

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final pageCount = srcDoc.pages.count;

    final compressionLevel = _mapCompressionLevel(quality);
    final destDoc = syncfusion.PdfDocument();
    destDoc.compressionLevel = compressionLevel;

    for (int i = 0; i < pageCount; i++) {
      final template = srcDoc.pages[i].createTemplate();
      destDoc.pages.add().graphics.drawPdfTemplate(template, ui.Offset.zero);
    }

    srcDoc.dispose();
    final bytes = await destDoc.save();
    destDoc.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Merge worker for background isolate execution.
  /// Params: files (List<Uint8List>)
  static Future<Uint8List> isolateMergeWorker(
      Map<String, dynamic> params) async {
    final filesData =
        (params['files'] as List<dynamic>).cast<Uint8List>();

    final mergedDoc = syncfusion.PdfDocument();

    for (final fileBytes in filesData) {
      final doc = syncfusion.PdfDocument(inputBytes: fileBytes);
      for (int j = 0; j < doc.pages.count; j++) {
        final page = doc.pages[j];
        final template = page.createTemplate();
        final pageSize = page.size;

        final section = mergedDoc.sections!.add();
        section.pageSettings.size = pageSize;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(
              template,
              ui.Offset.zero,
            );
      }
      doc.dispose();
    }

    final bytes = await mergedDoc.save();
    mergedDoc.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Split all pages worker for background isolate execution.
  /// Params: inputBytes (Uint8List)
  /// Returns: List<Uint8List> — one per page
  static Future<List<Uint8List>> isolateSplitAllPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes']));

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final pageCount = srcDoc.pages.count;
    final results = <Uint8List>[];

    for (int i = 0; i < pageCount; i++) {
      final page = srcDoc.pages[i];
      final template = page.createTemplate();
      final pageSize = page.size;

      final newDoc = syncfusion.PdfDocument();
      newDoc.pageSettings.size = pageSize;
      newDoc.pageSettings.margins.all = 0;
      newDoc.pages.add().graphics.drawPdfTemplate(
            template,
            ui.Offset.zero,
          );

      final bytes = await newDoc.save();
      newDoc.dispose();
      results.add(Uint8List.fromList(bytes));
    }

    srcDoc.dispose();
    return results;
  }

  /// Extract pages worker for background isolate execution.
  /// Params: inputBytes (Uint8List), pageNumbers (List<int>) — 1-indexed
  static Future<Uint8List> isolateExtractPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageNumbers =
        (params['pageNumbers'] as List<dynamic>).cast<int>();

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final newDoc = syncfusion.PdfDocument();

    for (final pageNum in pageNumbers) {
      final pageIndex = pageNum - 1;
      final page = srcDoc.pages[pageIndex];
      final template = page.createTemplate();
      final pageSize = page.size;

      final section = newDoc.sections!.add();
      section.pageSettings.size = pageSize;
      section.pageSettings.margins.all = 0;
      section.pages.add().graphics.drawPdfTemplate(
            template,
            ui.Offset.zero,
          );
    }

    srcDoc.dispose();
    final bytes = await newDoc.save();
    newDoc.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Split by chunks worker for background isolate execution.
  /// Params: inputBytes (Uint8List), pageSize (int)
  /// Returns: List<Uint8List> — one per chunk
  static Future<List<Uint8List>> isolateSplitByChunksWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageSize = params['pageSize'] as int;

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final pageCount = srcDoc.pages.count;
    final results = <Uint8List>[];

    for (int i = 0; i < pageCount; i += pageSize) {
      final newDoc = syncfusion.PdfDocument();
      final end = (i + pageSize < pageCount) ? i + pageSize : pageCount;

      for (int j = i; j < end; j++) {
        final page = srcDoc.pages[j];
        final template = page.createTemplate();
        final pageSize = page.size;

        final section = newDoc.sections!.add();
        section.pageSettings.size = pageSize;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(
              template,
              ui.Offset.zero,
            );
      }

      final bytes = await newDoc.save();
      newDoc.dispose();
      results.add(Uint8List.fromList(bytes));
    }

    srcDoc.dispose();
    return results;
  }

  /// Split selected pages worker for background isolate execution.
  /// Each selected page becomes its own independent PDF.
  /// Params: inputBytes (Uint8List), pageNumbers (List<int>) — 1-indexed
  /// Returns: List<Uint8List> — one per selected page
  static Future<List<Uint8List>> isolateSplitSelectedPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageNumbers =
        (params['pageNumbers'] as List<dynamic>).cast<int>();

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final results = <Uint8List>[];

    for (final pageNum in pageNumbers) {
      final pageIndex = pageNum - 1;
      final page = srcDoc.pages[pageIndex];
      final template = page.createTemplate();
      final pageSize = page.size;

      final newDoc = syncfusion.PdfDocument();
      newDoc.pageSettings.size = pageSize;
      newDoc.pageSettings.margins.all = 0;
      newDoc.pages.add().graphics.drawPdfTemplate(
            template,
            ui.Offset.zero,
          );

      final bytes = await newDoc.save();
      newDoc.dispose();
      results.add(Uint8List.fromList(bytes));
    }

    srcDoc.dispose();
    return results;
  }

  /// Convert to images worker for background isolate execution.
  /// Handles image encoding (JPEG/PNG) off the main thread.
  /// Params: renderedPages (List<Uint8List>), format (String)
  static Future<List<Uint8List>> isolateEncodeImagesWorker(
      Map<String, dynamic> params) async {
    final renderedPages =
        (params['renderedPages'] as List<dynamic>).cast<Uint8List>();
    final format = params['format'] as String;
    final results = <Uint8List>[];

    for (final pageBytes in renderedPages) {
      final decodedImage = img.decodeImage(pageBytes);
      if (decodedImage != null) {
        if (format == 'jpg') {
          results.add(Uint8List.fromList(
              img.encodeJpg(decodedImage, quality: 95)));
        } else {
          results.add(Uint8List.fromList(img.encodePng(decodedImage)));
        }
      }
    }
    return results;
  }

  // ─── Pipeline Manager ────────────────────────────────────────────────

  /// Orchestrates a complete PDF operation pipeline with isolate offloading.
  /// Reads source bytes, dispatches to background isolate, writes results.
  Future<dynamic> executePipeline({
    required PdfOperationType operation,
    required String inputPath,
    required Map<String, dynamic> operationParams,
    String? outputDir,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = outputDir != null
        ? Directory(outputDir)
        : await getSaveDir();

    onProgress?.call(0.1);

    switch (operation) {
      case PdfOperationType.compress:
        onProgress?.call(0.2);
        final inputBytes = File(inputPath).readAsBytesSync();
        final resultBytes = await _runIsolate(
          isolateCompressWorker,
          {
            'inputBytes': inputBytes,
            ...operationParams,
          },
        ) as Uint8List;

        final outputPath = _writeResultFile(
          saveDir,
          '${operationParams['outputBaseName'] ?? 'compressed'}_${DateTime.now().millisecondsSinceEpoch}',
          'pdf',
          resultBytes,
        );
        onProgress?.call(1.0);
        return outputPath;

      case PdfOperationType.merge:
        onProgress?.call(0.2);
        final inputPaths = operationParams['inputPaths'] as List<String>;
        final filesData = inputPaths
            .map((p) => File(p).readAsBytesSync())
            .map((b) => Uint8List.fromList(b))
            .toList();

        final resultBytes = await _runIsolate(
          isolateMergeWorker,
          {'files': filesData},
        ) as Uint8List;

        final outputPath = _writeResultFile(
          saveDir,
          '${operationParams['outputBaseName'] ?? 'merged'}_${DateTime.now().millisecondsSinceEpoch}',
          'pdf',
          resultBytes,
        );
        onProgress?.call(1.0);
        return outputPath;

      case PdfOperationType.split:
        onProgress?.call(0.2);
        final inputBytes = File(inputPath).readAsBytesSync();
        final splitMode = operationParams['splitMode'] as String;

        List<Uint8List> results;
        if (splitMode == 'extract') {
          final singleResult = await _runIsolate(
            isolateExtractPagesWorker,
            {
              'inputBytes': inputBytes,
              'pageNumbers': operationParams['pageNumbers'],
            },
          ) as Uint8List;
          results = [singleResult];
        } else if (splitMode == 'chunks') {
          results = await _runIsolate(
            isolateSplitByChunksWorker,
            {
              'inputBytes': inputBytes,
              'pageSize': operationParams['pageSize'],
            },
          ) as List<Uint8List>;
        } else {
          results = await _runIsolate(
            isolateSplitAllPagesWorker,
            {'inputBytes': inputBytes},
          ) as List<Uint8List>;
        }

        final outputPaths = <String>[];
        final baseName =
            operationParams['outputBaseName'] as String? ?? 'split';
        for (int i = 0; i < results.length; i++) {
          final path = _writeResultFile(
            saveDir,
            '${baseName}_part_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
            'pdf',
            results[i],
          );
          outputPaths.add(path);
        }
        onProgress?.call(1.0);
        return outputPaths;

      case PdfOperationType.convertToImages:
        onProgress?.call(0.2);
        final format = operationParams['format'] as String? ?? 'png';
        final dpi = operationParams['dpi'] as int? ?? 150;

        final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
        final pageCount = pdfDoc.pagesCount;
        final scale = dpi / 72.0;
        final renderedPages = <Uint8List>[];

        for (int i = 1; i <= pageCount; i++) {
          final page = await pdfDoc.getPage(i);
          final pageImage = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.png,
          );
          if (pageImage != null) {
            renderedPages.add(pageImage.bytes);
          }
          await page.close();
        }
        await pdfDoc.close();

        onProgress?.call(0.6);

        final encodedResults = await _runIsolate(
          isolateEncodeImagesWorker,
          {
            'renderedPages': renderedPages,
            'format': format,
          },
        ) as List<Uint8List>;

        final outputPaths = <String>[];
        final baseName =
            operationParams['outputBaseName'] as String? ?? 'page';
        for (int i = 0; i < encodedResults.length; i++) {
          final path = _writeResultFile(
            saveDir,
            '${baseName}_page_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
            format == 'jpg' ? 'jpg' : 'png',
            encodedResults[i],
          );
          outputPaths.add(path);
        }
        onProgress?.call(1.0);
        return outputPaths;
    }
  }

  /// Helper to run a function in a background isolate.
  Future<dynamic> _runIsolate(
    FutureOr<dynamic> Function(Map<String, dynamic>) callback,
    Map<String, dynamic> params,
  ) async {
    return await compute(callback, params);
  }

  /// Helper to write result bytes to a file.
  String _writeResultFile(
    Directory dir,
    String baseName,
    String extension,
    Uint8List bytes,
  ) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final filePath = '${dir.path}/$baseName.$extension';
    File(filePath).writeAsBytesSync(bytes, flush: true);
    return filePath;
  }
}

/// Operation types for the PDF pipeline manager.
enum PdfOperationType { compress, merge, split, convertToImages }
