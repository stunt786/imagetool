import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

import 'pdf_compression_engine.dart';
import 'pdf_ocr_service.dart';

/// Core service for all PDF processing operations.
/// Uses syncfusion_flutter_pdf for reading/manipulating existing PDFs
/// and the pdf package for creating new PDFs.
class PdfService {
  PdfService._();

  static final instance = PdfService._();

  /// Working directory for intermediate PDF artifacts.
  ///
  /// Always app-private: public destinations are reached by publishing the
  /// finished output through MediaStore / SAF (see [PublicStorage]), which
  /// scoped storage requires on Android 10+.
  Future<Directory> getSaveDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(base.path, 'PixelTools', 'PDFs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates a unique filename with the given extension.
  static String _generateFileName(String baseName, String extension) {
    var sanitizedBase =
        path.basename(baseName).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');
    if (sanitizedBase.toLowerCase().startsWith('pixeltools_')) {
      sanitizedBase = sanitizedBase.substring('pixeltools_'.length);
    } else if (sanitizedBase.toLowerCase().startsWith('pixeltools')) {
      sanitizedBase = sanitizedBase.substring('pixeltools'.length);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'pixeltools_${sanitizedBase}_$timestamp.$extension';
  }

  /// Generates a PNG thumbnail for page 1 of a PDF file using pdfx.
  /// Caches the generated thumbnail in the temporary directory.
  Future<String?> renderPdfThumbnail(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return null;

      final cacheDir = await getTemporaryDirectory();
      final stat = await file.stat();
      final thumbName =
          'pdf_thumb_${path.basenameWithoutExtension(pdfPath)}_${stat.modified.millisecondsSinceEpoch}.png';
      final thumbFile = File(path.join(cacheDir.path, thumbName));
      if (await thumbFile.exists()) {
        return thumbFile.path;
      }

      final pdfDoc = await pdfx.PdfDocument.openFile(pdfPath);
      final page = await pdfDoc.getPage(1);
      final scale = 250.0 / page.width;
      final pageImage = await page.render(
        width: 250,
        height: (page.height * scale).clamp(100.0, 500.0),
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      await pdfDoc.close();

      if (pageImage != null) {
        await thumbFile.writeAsBytes(pageImage.bytes, flush: true);
        return thumbFile.path;
      }
    } catch (_) {}
    return null;
  }

  // ─── Compress PDF ───────────────────────────────────────────────────

  /// Compresses [inputPath] into [outputPath] on a background isolate using
  /// the memory-safe PDF compression engine. [outputPath] always receives a
  /// valid PDF (the compressed document, or a copy of the original when no
  /// reduction was possible).
  static Future<PdfCompressionOutcome> compressPdfFile({
    required String inputPath,
    required String outputPath,
    required double quality,
    PdfCompressionPreset? preset,
    void Function(double progress)? onProgress,
  }) {
    return PdfCompressionEngine.compressFileInIsolate(
      inputPath: inputPath,
      outputPath: outputPath,
      qualityFactor: quality,
      preset: preset,
      onProgress: onProgress,
    );
  }

  /// Compresses a PDF file by rebuilding it and re-encoding its embedded
  /// images. [quality] ranges from 0.1 (smallest) to 1.0 (best quality).
  /// Returns the path to the compressed file.
  Future<String> compressPdf({
    required String inputPath,
    required double quality,
    PdfCompressionPreset? preset,
    String? outputBaseName,
    void Function(double progress)? onProgress,
    bool watermark = false,
    Uint8List? watermarkIconBytes,
    String watermarkText = 'PixelTools',
    int watermarkColorHex = 0xFFFFFFFF,
    double watermarkOpacity = 0.7,
    int watermarkPositionIndex = 4,
    bool useWatermarkLogo = true,
  }) async {
    final saveDir = await getSaveDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = path.join(saveDir.path, 'pixeltools_$timestamp.pdf');

    await PdfCompressionEngine.compressFile(
      inputPath: inputPath,
      outputPath: outputPath,
      preset: preset ?? PdfCompressionPreset.forQualityFactor(quality),
      onProgress: onProgress,
    );

    if (watermark) {
      try {
        final bytes = await File(outputPath).readAsBytes();
        final watermarked = _watermarkPdfBytes(bytes, <String, dynamic>{
          'applyWatermark': true,
          'watermarkText': watermarkText,
          'watermarkColor': watermarkColorHex,
          'watermarkOpacity': watermarkOpacity,
          'watermarkPosition': watermarkPositionIndex,
          'useWatermarkLogo': useWatermarkLogo,
          'iconBytes': watermarkIconBytes,
        });
        await File(outputPath).writeAsBytes(watermarked, flush: true);
      } catch (_) {
        // Watermarking is best-effort; the compressed file stays valid.
      }
    }

    return outputPath;
  }

  /// Last-resort fallback for PDFs whose embedded images use an encoding the
  /// pure-Dart engine cannot decode (JPEG 2000, JBIG2, CCITT).
  ///
  /// Pages are rendered with the platform PDF renderer one at a time, JPEG
  /// encoded at the level's quality and rebuilt into a new document. This is
  /// lossy: the text layer is not preserved. The result is validated with
  /// Syncfusion and returned only when it is valid and smaller than
  /// [inputLength]; otherwise null is returned and the caller keeps the
  /// original file.
  Future<Uint8List?> rasterCompressPdf({
    required String inputPath,
    required int inputLength,
    required double quality,
    int maxPages = 24,
    int maxPixelsPerPage = 4000000,
    void Function(double progress)? onProgress,
  }) async {
    final preset = PdfCompressionPreset.forQualityFactor(quality);
    final dpi = quality >= 0.7
        ? 150.0
        : quality >= 0.4
            ? 120.0
            : quality >= 0.25
                ? 100.0
                : 85.0;

    pdfx.PdfDocument? document;
    try {
      document = await pdfx.PdfDocument.openFile(inputPath);
      final pageCount = document.pagesCount;
      if (pageCount <= 0 || pageCount > maxPages) return null;

      final pages = <PdfRasterPage>[];
      var accumulated = 0;

      for (var index = 1; index <= pageCount; index++) {
        pdfx.PdfPage? page;
        try {
          page = await document.getPage(index);
          final pageWidth = page.width;
          final pageHeight = page.height;
          if (pageWidth <= 0 || pageHeight <= 0) return null;

          var renderWidth = pageWidth / 72.0 * dpi;
          var renderHeight = pageHeight / 72.0 * dpi;
          final pixels = renderWidth * renderHeight;
          if (pixels > maxPixelsPerPage && pixels > 0) {
            final factor = math.sqrt(maxPixelsPerPage / pixels);
            renderWidth *= factor;
            renderHeight *= factor;
          }
          renderWidth = renderWidth.clamp(32.0, 10000.0);
          renderHeight = renderHeight.clamp(32.0, 10000.0);

          final rendered = await page.render(
            width: renderWidth,
            height: renderHeight,
            format: pdfx.PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) return null;

          final encoded = await _encodeRasterPage(
            rendered.bytes,
            preset.jpegQuality,
            preset.maxImageLongSide,
          );
          if (encoded == null) return null;

          accumulated += encoded.bytes.length;
          // Bail out as soon as the raster version cannot possibly win.
          if (accumulated >= inputLength) return null;

          pages.add(
            PdfRasterPage(
              jpegBytes: encoded.bytes,
              imageWidth: encoded.width,
              imageHeight: encoded.height,
              pageWidth: pageWidth,
              pageHeight: pageHeight,
            ),
          );
        } catch (_) {
          return null;
        } finally {
          try {
            await page?.close();
          } catch (_) {}
        }
        onProgress?.call(index / pageCount);
      }

      final bytes = PdfRasterWriter.build(pages);
      if (bytes.length >= inputLength) return null;

      // Independent validation with a second PDF implementation before the
      // rasterised document replaces the original.
      final check = syncfusion.PdfDocument(inputBytes: bytes);
      try {
        if (check.pages.count != pages.length) return null;
      } finally {
        check.dispose();
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      try {
        await document?.close();
      } catch (_) {}
    }
  }

  /// Decodes a rendered page and re-encodes it as JPEG on a background
  /// isolate so the UI thread stays responsive.
  static Future<_EncodedRasterPage?> _encodeRasterPage(
    Uint8List renderedBytes,
    int quality,
    int maxLongSide,
  ) async {
    try {
      final result = await compute(_rasterEncodeWorker, <String, dynamic>{
        'bytes': renderedBytes,
        'quality': quality,
        'maxLongSide': maxLongSide,
      });
      if (result == null) return null;
      return _EncodedRasterPage(
        bytes: result['bytes'] as Uint8List,
        width: (result['width'] as num).toInt(),
        height: (result['height'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _rasterEncodeWorker(Map<String, dynamic> params) {
    var decoded =
        img.decodeImage(Uint8List.fromList(List<int>.from(params['bytes'] as List)));
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    final maxLongSide = (params['maxLongSide'] as num?)?.toInt() ?? 0;
    final longSide = math.max(decoded.width, decoded.height);
    if (maxLongSide > 0 && longSide > maxLongSide) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(
          decoded,
          width: maxLongSide,
          interpolation: img.Interpolation.average,
        );
      } else {
        decoded = img.copyResize(
          decoded,
          height: maxLongSide,
          interpolation: img.Interpolation.average,
        );
      }
    }
    final quality = (params['quality'] as num?)?.toInt() ?? 70;
    final solid = _flattenAlpha(decoded);
    return <String, dynamic>{
      'bytes': Uint8List.fromList(img.encodeJpg(solid, quality: quality)),
      'width': solid.width,
      'height': solid.height,
    };
  }

  /// Composites [image] onto a solid white background if it has transparency,
  /// preventing blank black image outputs in formats that don't support alpha.
  static img.Image _flattenAlpha(img.Image image) {
    if (!image.hasAlpha) return image;
    final flattened = img.Image(width: image.width, height: image.height);
    img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flattened, image);
    return flattened;
  }

  // ─── Merge PDFs ─────────────────────────────────────────────────────

  /// Merges multiple PDF files into a single document.
  /// [inputPaths] are the paths to the PDF files in order.
  /// Returns the path to the merged file.
  Future<String> mergePdfs({
    required List<String> inputPaths,
    required String outputBaseName,
    void Function(double progress)? onProgress,
    bool watermark = false,
    Uint8List? watermarkIconBytes,
    String watermarkText = 'PixelTools',
    int watermarkColorHex = 0xFFFFFFFF,
    double watermarkOpacity = 0.7,
    int watermarkPositionIndex = 4,
    bool useWatermarkLogo = true,
  }) async {
    if (inputPaths.isEmpty) {
      throw ArgumentError('At least one PDF file is required');
    }

    final saveDir = await getSaveDir();
    final outputPath =
        path.join(saveDir.path, _generateFileName(outputBaseName, 'pdf'));

    // Use Syncfusion for reliable, fast PDF merging with section reuse
    final mergedDoc = syncfusion.PdfDocument();
    mergedDoc.pageSettings.margins.all = 0;

    syncfusion.PdfSection? currentSection;
    ui.Size? currentSectionSize;
    syncfusion.PdfPageRotateAngle? currentSectionRotation;

    for (int i = 0; i < inputPaths.length; i++) {
      final inputBytes = File(inputPaths[i]).readAsBytesSync();
      final doc = syncfusion.PdfDocument(inputBytes: inputBytes);

      for (int j = 0; j < doc.pages.count; j++) {
        final page = doc.pages[j];
        final pageSize = page.size;

        if (currentSection == null ||
            currentSectionSize != pageSize ||
            currentSectionRotation != page.rotation) {
          final newSection = mergedDoc.sections!.add();
          newSection.pageSettings.size = pageSize;
          newSection.pageSettings.rotate = page.rotation;
          newSection.pageSettings.orientation = (pageSize.width > pageSize.height)
              ? syncfusion.PdfPageOrientation.landscape
              : syncfusion.PdfPageOrientation.portrait;
          newSection.pageSettings.margins.all = 0;
          currentSection = newSection;
          currentSectionSize = pageSize;
          currentSectionRotation = page.rotation;
        }

        final newPage = currentSection.pages.add();
        newPage.rotation = page.rotation;
        final template = page.createTemplate();
        newPage.graphics.drawPdfTemplate(
          template,
          ui.Offset.zero,
          pageSize,
        );
        if (watermark) {
          applyWatermarkToSyncfusionPage(
            newPage,
            iconBytes: watermarkIconBytes,
            text: watermarkText,
            colorHex: watermarkColorHex,
            opacity: watermarkOpacity,
            positionIndex: watermarkPositionIndex,
            useAppLogo: useWatermarkLogo,
          );
        }
      }

      doc.dispose();
      onProgress?.call((i + 1) / inputPaths.length);
    }

    final List<int> bytes = await mergedDoc.save();
    mergedDoc.dispose();

    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }

  /// Creates a single PDF document from one or more image files.
  Future<String> createPdfFromImages({
    required List<String> imagePaths,
    String? outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final saveDir = await getSaveDir();
    final base = outputBaseName ??
        (imagePaths.isNotEmpty
            ? path.basenameWithoutExtension(imagePaths.first)
            : 'document');
    final outName = _generateFileName(base, 'pdf');
    final outPath = path.join(saveDir.path, outName);

    final doc = syncfusion.PdfDocument();
    for (int i = 0; i < imagePaths.length; i++) {
      final imgPath = imagePaths[i];
      final file = File(imgPath);
      if (!await file.exists() || await file.length() == 0) continue;
      final bytes = await file.readAsBytes();
      syncfusion.PdfBitmap image;
      try {
        image = syncfusion.PdfBitmap(bytes);
      } catch (_) {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final pngBytes = Uint8List.fromList(img.encodePng(decoded));
        image = syncfusion.PdfBitmap(pngBytes);
      }
      final section = doc.sections!.add();
      section.pageSettings.size =
          ui.Size(image.width.toDouble(), image.height.toDouble());
      section.pageSettings.margins.all = 0;
      final page = section.pages.add();
      page.graphics.drawImage(
        image,
        ui.Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );
      onProgress?.call((i + 1) / imagePaths.length);
    }

    final bytes = await doc.save();
    doc.dispose();
    final outFile = File(outPath);
    await outFile.writeAsBytes(bytes, flush: true);
    return outPath;
  }

  // ─── Split PDF ──────────────────────────────────────────────────────

  /// Splits a PDF into individual page files.
  /// Returns a list of paths to the split files.
  Future<List<String>> splitPdfAllPages({
    required String inputPath,
    required String outputBaseName,
    void Function(double progress)? onProgress,
  }) async {
    final syncDoc =
        syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
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

      final fileName =
          _generateFileName('${outputBaseName}_page_${i + 1}', 'pdf');
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

    final syncDoc =
        syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
    final pageCount = syncDoc.pages.count;
    final saveDir = await getSaveDir();

    // Validate page numbers
    for (final pageNum in pageNumbers) {
      if (pageNum < 1 || pageNum > pageCount) {
        syncDoc.dispose();
        throw ArgumentError(
            'Page number $pageNum is out of range (1-$pageCount)');
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

    final syncDoc =
        syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
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

      final fileName =
          _generateFileName('${outputBaseName}_part_$chunkIndex', 'pdf');
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
  /// [pageNumbers] (optional) 1-indexed list of specific pages to convert.
  /// Returns a list of paths to the converted image files.
  Future<List<String>> convertPdfToImages({
    required String inputPath,
    required String format,
    required String outputBaseName,
    int dpi = 150,
    List<int>? pageNumbers,
    void Function(double progress)? onProgress,
  }) async {
    final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
    final pageCount = pdfDoc.pagesCount;
    final saveDir = await getSaveDir();
    final outputPaths = <String>[];

    final scale = dpi / 72.0;
    final pages = (pageNumbers != null && pageNumbers.isNotEmpty)
        ? pageNumbers.where((p) => p >= 1 && p <= pageCount).toList()
        : List.generate(pageCount, (i) => i + 1);

    for (int idx = 0; idx < pages.length; idx++) {
      final i = pages[idx];
      final page = await pdfDoc.getPage(i);

      final pageImage = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );

      if (pageImage != null) {
        final decodedImage = img.decodeImage(pageImage.bytes);
        if (decodedImage != null) {
          final solidImage = _flattenAlpha(decodedImage);
          Uint8List outputBytes;
          String extension;

          if (format == 'jpg') {
            outputBytes =
                Uint8List.fromList(img.encodeJpg(solidImage, quality: 95));
            extension = 'jpg';
          } else {
            outputBytes = Uint8List.fromList(img.encodePng(solidImage));
            extension = 'png';
          }

          final fileName =
              _generateFileName('${outputBaseName}_page_$i', extension);
          final outputPath = path.join(saveDir.path, fileName);
          await File(outputPath).writeAsBytes(outputBytes);
          outputPaths.add(outputPath);
        }
      }

      onProgress?.call((idx + 1) / pages.length);
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
    final syncDoc =
        syncfusion.PdfDocument(inputBytes: File(inputPath).readAsBytesSync());
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
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
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
        backgroundColor: '#FFFFFF',
      );

      await pdfDoc.close();
      return pageImage?.bytes;
    } catch (_) {
      return null;
    }
  }

  /// Renders a specific page at high resolution (e.g. dpi 200) as image bytes (JPG or PNG).
  Future<Uint8List?> renderPageAsImage({
    required String inputPath,
    required int pageNumber,
    int dpi = 200,
    String format = 'jpg',
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      final pdfDoc = await pdfx.PdfDocument.openFile(inputPath);
      if (pageNumber < 1 || pageNumber > pdfDoc.pagesCount) {
        await pdfDoc.close();
        return null;
      }

      final page = await pdfDoc.getPage(pageNumber);
      final scale = dpi / 72.0;

      final pageImage = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );

      await pdfDoc.close();
      if (pageImage == null) return null;

      final decodedImage = img.decodeImage(pageImage.bytes);
      if (decodedImage == null) return pageImage.bytes;
      final solidImage = _flattenAlpha(decodedImage);

      if (format.toLowerCase() == 'png') {
        return Uint8List.fromList(img.encodePng(solidImage));
      } else {
        return Uint8List.fromList(img.encodeJpg(solidImage, quality: 95));
      }
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

  /// Applies a watermark (app icon + text with transparency and pill backdrop)
  /// onto a Syncfusion PDF page graphics context.
  static void applyWatermarkToSyncfusionPage(
    syncfusion.PdfPage page, {
    Uint8List? iconBytes,
    required String text,
    required int colorHex,
    required double opacity,
    required int positionIndex,
    bool useAppLogo = true,
  }) {
    if (text.isEmpty &&
        (!useAppLogo || iconBytes == null || iconBytes.isEmpty)) {
      return;
    }

    final pageSize = page.size;
    final graphics = page.graphics;
    final state = graphics.save();

    try {
      final safeOpacity = opacity.clamp(0.05, 1.0);
      graphics.setTransparency(safeOpacity);

      final r = (colorHex >> 16) & 0xFF;
      final g = (colorHex >> 8) & 0xFF;
      final b = colorHex & 0xFF;
      final textColor = syncfusion.PdfColor(r, g, b);
      final textBrush = syncfusion.PdfSolidBrush(textColor);

      final fontSize = (pageSize.width * 0.022).clamp(9.0, 16.0);
      final font = syncfusion.PdfStandardFont(
        syncfusion.PdfFontFamily.helvetica,
        fontSize,
        style: syncfusion.PdfFontStyle.bold,
      );

      final textSize =
          text.isNotEmpty ? font.measureString(text) : const ui.Size(0, 0);
      final hasIcon = useAppLogo && iconBytes != null && iconBytes.isNotEmpty;
      final iconSize = fontSize * 1.35;
      final spacing = hasIcon && text.isNotEmpty ? fontSize * 0.4 : 0.0;

      final contentWidth =
          (hasIcon ? iconSize : 0.0) + spacing + textSize.width;
      final contentHeight = math.max(hasIcon ? iconSize : 0.0, textSize.height);

      const margin = 18.0;
      final paddingH = fontSize * 0.65;
      final paddingV = fontSize * 0.35;
      final pillWidth = contentWidth + paddingH * 2;
      final pillHeight = contentHeight + paddingV * 2;

      double x;
      double y;

      switch (positionIndex) {
        case 0: // Top-Left
          x = margin;
          y = margin;
          break;
        case 1: // Top-Right
          x = pageSize.width - pillWidth - margin;
          y = margin;
          break;
        case 2: // Center
          x = (pageSize.width - pillWidth) / 2;
          y = (pageSize.height - pillHeight) / 2;
          break;
        case 3: // Bottom-Left
          x = margin;
          y = pageSize.height - pillHeight - margin;
          break;
        case 4: // Bottom-Right
        default:
          x = pageSize.width - pillWidth - margin;
          y = pageSize.height - pillHeight - margin;
          break;
      }

      x = x.clamp(0.0, math.max(0.0, pageSize.width - pillWidth));
      y = y.clamp(0.0, math.max(0.0, pageSize.height - pillHeight));

      double curX = x + paddingH;
      if (hasIcon) {
        try {
          final iconBitmap = syncfusion.PdfBitmap(iconBytes);
          final iconY = y + (pillHeight - iconSize) / 2;
          graphics.drawImage(
            iconBitmap,
            ui.Rect.fromLTWH(curX, iconY, iconSize, iconSize),
          );
          curX += iconSize + spacing;
        } catch (_) {}
      }

      if (text.isNotEmpty) {
        final textY = y + (pillHeight - textSize.height) / 2;
        graphics.drawString(
          text,
          font,
          brush: textBrush,
          bounds:
              ui.Rect.fromLTWH(curX, textY, textSize.width, textSize.height),
        );
      }
    } catch (_) {
    } finally {
      graphics.restore(state);
    }
  }

  // Keep worker parameters compatible with every caller. Older pipelines used
  // `watermark`, while the feature notifiers use the clearer `applyWatermark`.
  // Normalising here prevents a silent loss of the user's watermark settings.
  static bool _workerWatermarkEnabled(Map<String, dynamic> params) =>
      params['applyWatermark'] as bool? ??
      params['watermark'] as bool? ??
      false;

  static Uint8List? _workerWatermarkIcon(Map<String, dynamic> params) =>
      params['iconBytes'] as Uint8List? ??
      params['watermarkIconBytes'] as Uint8List?;

  static int _workerWatermarkColor(Map<String, dynamic> params) =>
      params['watermarkColor'] as int? ??
      params['watermarkColorHex'] as int? ??
      0xFFFFFFFF;

  static int _workerWatermarkPosition(Map<String, dynamic> params) =>
      params['watermarkPosition'] as int? ??
      params['watermarkPositionIndex'] as int? ??
      4;

  /// Applies the app watermark to an existing PDF on a background isolate.
  /// Returns null when watermarking failed.
  static Future<Uint8List?> watermarkPdfBytes({
    required Uint8List inputBytes,
    required String text,
    required int colorHex,
    required double opacity,
    required int positionIndex,
    required bool useAppLogo,
    Uint8List? iconBytes,
  }) async {
    if (text.trim().isEmpty &&
        (!useAppLogo || iconBytes == null || iconBytes.isEmpty)) {
      return inputBytes;
    }
    try {
      return await compute(isolateWatermarkWorker, <String, dynamic>{
        'inputBytes': inputBytes,
        'applyWatermark': true,
        'watermarkText': text,
        'watermarkColor': colorHex,
        'watermarkOpacity': opacity,
        'watermarkPosition': positionIndex,
        'useWatermarkLogo': useAppLogo,
        'iconBytes': iconBytes,
      });
    } catch (_) {
      return null;
    }
  }

  /// Watermark worker for background isolate execution.
  /// Params: inputBytes (Uint8List) plus the standard watermark parameters.
  static Future<Uint8List> isolateWatermarkWorker(
      Map<String, dynamic> params) async {
    final inputBytes =
        Uint8List.fromList(List<int>.from(params['inputBytes'] as List));
    return _watermarkPdfBytes(inputBytes, params);
  }

  /// Draws the watermark over every page of [inputBytes] using Syncfusion.
  static Uint8List _watermarkPdfBytes(
      Uint8List inputBytes, Map<String, dynamic> params) {
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

    final srcDoc = syncfusion.PdfDocument(inputBytes: inputBytes);
    final pageCount = srcDoc.pages.count;
    final destDoc = syncfusion.PdfDocument();
    try {
      for (int i = 0; i < pageCount; i++) {
        final template = srcDoc.pages[i].createTemplate();
        final section = destDoc.sections!.add();
        section.pageSettings.size = srcDoc.pages[i].size;
        section.pageSettings.margins.all = 0;
        final page = section.pages.add();
        page.graphics.drawPdfTemplate(template, ui.Offset.zero);
        applyWatermarkToSyncfusionPage(
          page,
          iconBytes: iconBytes,
          text: watermarkText,
          colorHex: colorHex,
          opacity: opacity,
          positionIndex: positionIndex,
          useAppLogo: useAppLogo,
        );
      }
      return Uint8List.fromList(destDoc.saveSync());
    } finally {
      srcDoc.dispose();
      destDoc.dispose();
    }
  }

  /// Compress worker for background isolate execution.
  ///
  /// Runs the memory-safe compression engine (which re-encodes embedded
  /// images and DEFLATEs uncompressed streams) and optionally applies the app
  /// watermark afterwards.
  ///
  /// Params: `inputPath` (preferred, avoids copying bytes between isolates) or
  /// `inputBytes`, `quality`, plus the standard watermark parameters.
  static Future<Uint8List> isolateCompressWorker(
      Map<String, dynamic> params) async {
    final inputPath = params['inputPath'] as String?;
    final Uint8List inputBytes;
    if (inputPath != null && inputPath.isNotEmpty) {
      inputBytes = await File(inputPath).readAsBytes();
    } else {
      inputBytes =
          Uint8List.fromList(List<int>.from(params['inputBytes'] as List));
    }

    final quality = (params['quality'] as num?)?.toDouble() ?? 0.5;
    final preset = PdfCompressionPreset.forQualityFactor(quality);

    Uint8List compressed;
    try {
      compressed = await PdfCompressionEngine.compressBytes(
        input: inputBytes,
        preset: preset,
      );
    } catch (_) {
      compressed = inputBytes;
    }

    if (!_workerWatermarkEnabled(params)) {
      return compressed;
    }

    try {
      return _watermarkPdfBytes(compressed, params);
    } catch (_) {
      return compressed;
    }
  }

  /// Merge worker for background isolate execution.
  /// Params: files (`List<Uint8List>`) or filePaths (`List<String>`)
  static Future<Uint8List> isolateMergeWorker(
      Map<String, dynamic> params) async {
    final filesData = (params['files'] as List<dynamic>?)?.cast<Uint8List>();
    final filePaths = (params['filePaths'] as List<dynamic>?)?.cast<String>();
    final applyWatermark = _workerWatermarkEnabled(params);
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

    final mergedDoc = syncfusion.PdfDocument();
    mergedDoc.pageSettings.margins.all = 0;

    syncfusion.PdfSection? currentSection;
    ui.Size? currentSectionSize;
    syncfusion.PdfPageRotateAngle? currentSectionRotation;

    final count = filePaths?.length ?? filesData?.length ?? 0;

    for (int i = 0; i < count; i++) {
      final syncfusion.PdfDocument doc;
      if (filePaths != null) {
        doc = syncfusion.PdfDocument(
            inputBytes: File(filePaths[i]).readAsBytesSync());
      } else {
        doc = syncfusion.PdfDocument(inputBytes: filesData![i]);
      }

      for (int j = 0; j < doc.pages.count; j++) {
        final page = doc.pages[j];
        final pageSize = page.size;

        if (currentSection == null ||
            currentSectionSize != pageSize ||
            currentSectionRotation != page.rotation) {
          currentSection = mergedDoc.sections!.add();
          currentSection.pageSettings.size = pageSize;
          currentSection.pageSettings.rotate = page.rotation;
          currentSection.pageSettings.orientation = (pageSize.width > pageSize.height)
              ? syncfusion.PdfPageOrientation.landscape
              : syncfusion.PdfPageOrientation.portrait;
          currentSection.pageSettings.margins.all = 0;
          currentSectionSize = pageSize;
          currentSectionRotation = page.rotation;
        }

        final newPage = currentSection.pages.add();
        newPage.rotation = page.rotation;
        final template = page.createTemplate();
        newPage.graphics.drawPdfTemplate(
          template,
          ui.Offset.zero,
          pageSize,
        );
        if (applyWatermark) {
          applyWatermarkToSyncfusionPage(
            newPage,
            iconBytes: iconBytes,
            text: watermarkText,
            colorHex: colorHex,
            opacity: opacity,
            positionIndex: positionIndex,
            useAppLogo: useAppLogo,
          );
        }
      }
      doc.dispose();
    }

    final bytes = await mergedDoc.save();
    mergedDoc.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Split all pages worker for background isolate execution.
  /// Params: inputBytes (Uint8List)
  /// Returns: List of Uint8List — one per page
  static Future<List<Uint8List>> isolateSplitAllPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes = Uint8List.fromList(List<int>.from(params['inputBytes']));
    final applyWatermark = _workerWatermarkEnabled(params);
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

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
      final newPage = newDoc.pages.add();
      newPage.graphics.drawPdfTemplate(
        template,
        ui.Offset.zero,
      );
      if (applyWatermark) {
        applyWatermarkToSyncfusionPage(
          newPage,
          iconBytes: iconBytes,
          text: watermarkText,
          colorHex: colorHex,
          opacity: opacity,
          positionIndex: positionIndex,
          useAppLogo: useAppLogo,
        );
      }

      final bytes = await newDoc.save();
      newDoc.dispose();
      results.add(Uint8List.fromList(bytes));
    }

    srcDoc.dispose();
    return results;
  }

  /// Extract pages worker for background isolate execution.
  /// Params: inputBytes (Uint8List), pageNumbers (List of int) — 1-indexed
  static Future<Uint8List> isolateExtractPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes = Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageNumbers = (params['pageNumbers'] as List<dynamic>).cast<int>();
    final applyWatermark = _workerWatermarkEnabled(params);
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

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
      final newPage = section.pages.add();
      newPage.graphics.drawPdfTemplate(
        template,
        ui.Offset.zero,
      );
      if (applyWatermark) {
        applyWatermarkToSyncfusionPage(
          newPage,
          iconBytes: iconBytes,
          text: watermarkText,
          colorHex: colorHex,
          opacity: opacity,
          positionIndex: positionIndex,
          useAppLogo: useAppLogo,
        );
      }
    }

    srcDoc.dispose();
    final bytes = await newDoc.save();
    newDoc.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Split by chunks worker for background isolate execution.
  /// Params: inputBytes (Uint8List), pageSize (int)
  /// Returns: List of Uint8List — one per chunk
  static Future<List<Uint8List>> isolateSplitByChunksWorker(
      Map<String, dynamic> params) async {
    final inputBytes = Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageSize = params['pageSize'] as int;
    final applyWatermark = _workerWatermarkEnabled(params);
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

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
        final newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(
          template,
          ui.Offset.zero,
        );
        if (applyWatermark) {
          applyWatermarkToSyncfusionPage(
            newPage,
            iconBytes: iconBytes,
            text: watermarkText,
            colorHex: colorHex,
            opacity: opacity,
            positionIndex: positionIndex,
            useAppLogo: useAppLogo,
          );
        }
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
  /// Params: inputBytes (Uint8List), pageNumbers (List of int) — 1-indexed
  /// Returns: List of Uint8List — one per selected page
  static Future<List<Uint8List>> isolateSplitSelectedPagesWorker(
      Map<String, dynamic> params) async {
    final inputBytes = Uint8List.fromList(List<int>.from(params['inputBytes']));
    final pageNumbers = (params['pageNumbers'] as List<dynamic>).cast<int>();
    final applyWatermark = _workerWatermarkEnabled(params);
    final iconBytes = _workerWatermarkIcon(params);
    final watermarkText = params['watermarkText'] as String? ?? 'PixelTools';
    final colorHex = _workerWatermarkColor(params);
    final opacity = (params['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
    final positionIndex = _workerWatermarkPosition(params);
    final useAppLogo = params['useWatermarkLogo'] as bool? ?? true;

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
      final newPage = newDoc.pages.add();
      newPage.graphics.drawPdfTemplate(
        template,
        ui.Offset.zero,
      );
      if (applyWatermark) {
        applyWatermarkToSyncfusionPage(
          newPage,
          iconBytes: iconBytes,
          text: watermarkText,
          colorHex: colorHex,
          opacity: opacity,
          positionIndex: positionIndex,
          useAppLogo: useAppLogo,
        );
      }

      final bytes = await newDoc.save();
      newDoc.dispose();
      results.add(Uint8List.fromList(bytes));
    }

    srcDoc.dispose();
    return results;
  }

  /// Convert to images worker for background isolate execution.
  /// Handles image encoding (JPEG/PNG) off the main thread.
  /// Params: renderedPages (List of Uint8List), format (String)
  static Future<List<Uint8List>> isolateEncodeImagesWorker(
      Map<String, dynamic> params) async {
    final renderedPages =
        (params['renderedPages'] as List<dynamic>).cast<Uint8List>();
    final format = params['format'] as String;
    final results = <Uint8List>[];

    for (final pageBytes in renderedPages) {
      final decodedImage = img.decodeImage(pageBytes);
      if (decodedImage != null) {
        final solid = _flattenAlpha(decodedImage);
        if (format == 'jpg') {
          results.add(
              Uint8List.fromList(img.encodeJpg(solid, quality: 95)));
        } else {
          results.add(Uint8List.fromList(img.encodePng(solid)));
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
    final saveDir =
        outputDir != null ? Directory(outputDir) : await getSaveDir();

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
        final baseName = operationParams['outputBaseName'] as String? ?? 'page';
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
    final sanitizedBase =
        path.basename(baseName).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');
    final filePath = path.join(dir.path, '$sanitizedBase.$extension');
    File(filePath).writeAsBytesSync(bytes, flush: true);
    return filePath;
  }
}

/// A rasterised page encoded for embedding in a rebuilt PDF.
class _EncodedRasterPage {
  const _EncodedRasterPage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Operation types for the PDF pipeline manager.
enum PdfOperationType { compress, merge, split, convertToImages }
