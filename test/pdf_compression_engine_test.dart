// Unit tests for the PDF compression engine and its service integration.
//
// The engine is pure Dart, so these tests build small PDFs on the fly with the
// `pdf` package, compress them, and assert the output is smaller, valid and
// still contains the expected structure.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pixeltools/core/services/pdf_compression_engine.dart';
import 'package:pixeltools/core/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Builds a small but valid PDF from raw object bodies.
Uint8List _buildPdf(List<String> objects, {String trailerExtra = ''}) {
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer.write('xref\n');
  buffer.write('0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n');
  buffer.write(
      '<< /Size ${objects.length + 1} /Root 1 0 R$trailerExtra >>\n');
  buffer.write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// Builds a PDF whose single page has an uncompressed (Flate-free) content
/// stream larger than the engine's minimum stream size.
Uint8List _uncompressedStreamPdf() {
  final painter = StringBuffer('BT /F1 24 Tf 72 700 Td (Hello compression) Tj ET\n');
  while (painter.length < 4096) {
    painter.write('% padding padding padding padding padding padding\n');
  }
  final payload = painter.toString();
  return _buildPdf(<String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${payload.length} >>\nstream\n$payload\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ]);
}

/// Builds a 640x800 noisy JPEG that is deliberately expensive to store, then
/// wraps it in a PDF page.
Future<Uint8List> _noisyJpegPdf() async {
  const width = 640;
  const height = 800;
  final raw = Uint8List(width * height * 3);
  var seed = 123456789;
  for (var i = 0; i < raw.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    raw[i] = (seed >> 16) & 0xFF;
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: raw.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));

  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(
        child: pw.Image(pw.MemoryImage(jpeg), fit: pw.BoxFit.contain),
      ),
    ),
  );
  return Uint8List.fromList(await document.save());
}

void main() {
  group('PdfCompressionEngine', () {
    test('re-encodes an embedded JPEG and shrinks the document', () async {
      final input = await _noisyJpegPdf();
      expect(utf8.decode(input.take(4).toList()), '%PDF');

      final preset = PdfCompressionPreset.forQualityFactor(0.5);
      final output = await PdfCompressionEngine.compressBytes(
        input: input,
        preset: preset,
      );

      expect(output.length, lessThan(input.length),
          reason: 'compressed output must be smaller than the input');
      expect(utf8.decode(output.take(4).toList()), '%PDF');
      expect(latin1.decode(output), contains('DCTDecode'));
      expect(latin1.decode(output), contains('startxref'));
    });

    test('never returns a larger file for an image-free PDF', () async {
      final input = await _noisyJpegPdf();
      // Strip the image entirely: a text/vector only document.
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Text('No images here at all'),
        ),
      );
      final textPdf = Uint8List.fromList(await document.save());

      final output = await PdfCompressionEngine.compressBytes(
        input: textPdf,
        preset: PdfCompressionPreset.forQualityFactor(0.5),
      );

      expect(output.length, lessThanOrEqualTo(textPdf.length));
      expect(utf8.decode(output.take(4).toList()), '%PDF');
      expect(input.isNotEmpty, isTrue);
    });

    test('deflates uncompressed streams', () async {
      final input = _uncompressedStreamPdf();
      final tempDir =
          await Directory.systemTemp.createTemp('pdfc_engine_test_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final inputPath = '${tempDir.path}/in.pdf';
      final outputPath = '${tempDir.path}/out.pdf';
      await File(inputPath).writeAsBytes(input, flush: true);

      final outcome = await PdfCompressionEngine.compressFile(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: PdfCompressionPreset.forQualityFactor(0.5),
      );

      expect(outcome.improved, isTrue);
      expect(outcome.streamsDeflated, greaterThanOrEqualTo(1));
      expect(outcome.pageCount, 1);
      expect(await File(outputPath).length(), lessThan(input.length));
      expect(latin1.decode(await File(outputPath).readAsBytes()),
          contains('/Filter /FlateDecode'));
    });

    test('leaves encrypted documents untouched', () async {
      final input = _buildPdf(
        <String>[
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [] /Count 0 >>',
          '<< /Length 0 >>\nstream\n\nendstream',
        ],
        trailerExtra: ' /Encrypt 3 0 R /ID [<0102> <0102>]',
      );
      final tempDir =
          await Directory.systemTemp.createTemp('pdfc_engine_enc_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final inputPath = '${tempDir.path}/in.pdf';
      final outputPath = '${tempDir.path}/out.pdf';
      await File(inputPath).writeAsBytes(input, flush: true);

      final outcome = await PdfCompressionEngine.compressFile(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: PdfCompressionPreset.forQualityFactor(0.5),
      );

      expect(outcome.improved, isFalse);
      expect(outcome.note, contains('Encrypted'));
      expect(await File(outputPath).length(), input.length);
    });

    test('rejects non-PDF input without throwing', () async {
      final input = Uint8List.fromList(utf8.encode('this is not a pdf'));
      final output = await PdfCompressionEngine.compressBytes(
        input: input,
        preset: PdfCompressionPreset.forQualityFactor(0.5),
      );
      expect(output.length, input.length);
    });

    test('output can be compressed again (idempotent, no crash)', () async {
      final input = await _noisyJpegPdf();
      final preset = PdfCompressionPreset.forQualityFactor(0.5);
      final first = await PdfCompressionEngine.compressBytes(
        input: input,
        preset: preset,
      );
      final second = await PdfCompressionEngine.compressBytes(
        input: first,
        preset: preset,
      );
      expect(utf8.decode(second.take(4).toList()), '%PDF');
      expect(second.length, lessThanOrEqualTo(first.length));
    });
  });

  group('PdfRasterWriter', () {
    PdfRasterPage page(int shade) {
      final image = img.Image(width: 120, height: 90);
      img.fill(image, color: img.ColorRgb8(shade, 100, 200));
      final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 70));
      return PdfRasterPage(
        jpegBytes: jpeg,
        imageWidth: image.width,
        imageHeight: image.height,
        pageWidth: 612,
        pageHeight: 792,
      );
    }

    test('builds a valid, openable multi-page PDF', () {
      final bytes = PdfRasterWriter.build(<PdfRasterPage>[
        page(10),
        page(80),
        page(150),
      ]);

      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(latin1.decode(bytes), contains('/Filter /DCTDecode'));
      expect(latin1.decode(bytes), contains('startxref'));

      final document = syncfusion.PdfDocument(inputBytes: bytes);
      try {
        expect(document.pages.count, 3);
        expect(document.pages[0].size.width, closeTo(612, 0.01));
        expect(document.pages[0].size.height, closeTo(792, 0.01));
      } finally {
        document.dispose();
      }
    });

    test('rejects an empty page list', () {
      expect(
        () => PdfRasterWriter.build(const <PdfRasterPage>[]),
        throwsArgumentError,
      );
    });
  });

  group('PdfService compression integration', () {
    test('isolateCompressWorker compresses without watermarking', () async {
      final input = await _noisyJpegPdf();
      final result = await PdfService.isolateCompressWorker(<String, dynamic>{
        'inputBytes': input,
        'quality': 0.5,
        'applyWatermark': false,
      });

      expect(result, isNotEmpty);
      expect(utf8.decode(result.take(4).toList()), '%PDF');
      expect(result.length, lessThan(input.length));
    });

    test('compressed output can still be watermarked by Syncfusion', () async {
      final input = await _noisyJpegPdf();
      final compressed =
          await PdfService.isolateCompressWorker(<String, dynamic>{
        'inputBytes': input,
        'quality': 0.5,
        'applyWatermark': false,
      });

      final watermarked = await PdfService.watermarkPdfBytes(
        inputBytes: compressed,
        text: 'PixelTools',
        colorHex: 0xFFFFFFFF,
        opacity: 0.6,
        positionIndex: 4,
        useAppLogo: false,
      );

      expect(watermarked, isNotNull);
      final bytes = watermarked!;
      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(compressed.length));
    });

    test('compressPdfFile runs in an isolate and reports progress', () async {
      final input = await _noisyJpegPdf();
      final tempDir =
          await Directory.systemTemp.createTemp('pdfc_isolate_test_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final inputPath = '${tempDir.path}/in.pdf';
      final outputPath = '${tempDir.path}/out.pdf';
      await File(inputPath).writeAsBytes(input, flush: true);

      final progress = <double>[];
      final outcome = await PdfService.compressPdfFile(
        inputPath: inputPath,
        outputPath: outputPath,
        quality: 0.5,
        onProgress: progress.add,
      );

      expect(outcome.improved, isTrue);
      expect(outcome.pageCount, 1);
      expect(await File(outputPath).length(), lessThan(input.length));
      expect(await File(outputPath).length(), outcome.outputBytes);
      expect(progress, isNotEmpty);
      expect(progress.last, greaterThan(0.5));
    });

    test('compressPdfFile copies the original when nothing can be saved',
        () async {
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Text('Already tiny and compressed'),
        ),
      );
      final input = Uint8List.fromList(await document.save());

      final tempDir =
          await Directory.systemTemp.createTemp('pdfc_isolate_copy_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      final inputPath = '${tempDir.path}/in.pdf';
      final outputPath = '${tempDir.path}/out.pdf';
      await File(inputPath).writeAsBytes(input, flush: true);

      final outcome = await PdfService.compressPdfFile(
        inputPath: inputPath,
        outputPath: outputPath,
        quality: 0.5,
      );

      expect(outcome.improved, isFalse);
      expect(await File(outputPath).length(), input.length);
      expect(outcome.note, isNotNull);
    });
  });
}
