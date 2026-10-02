import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pixeltools/core/services/pdf_compression_engine.dart';
import 'package:pixeltools/features/pdf_compress/models/pdf_compress_state.dart';
import 'package:pixeltools/features/pdf_compress/notifiers/pdf_compress_notifier.dart';
import 'package:pixeltools/features/pdf_compress/widgets/compression_settings_panel.dart';

Uint8List _buildCustomPdf(List<String> objects, {String trailerExtra = ''}) {
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

void main() {
  group('PdfCompressionPreset Parameters & Serialization', () {
    test('toMap and fromMap preserve all advanced parameters', () {
      final original = PdfCompressionPreset(
        jpegQuality: 75,
        colorImageQuality: 72,
        greyImageQuality: 62,
        monoImageQuality: 52,
        maxImageLongSide: 1800,
        maxDecodePixels: 25000000,
        jpegSkipBytesPerPixel: 0.42,
        deflateStreams: false,
        unembedSimpleFonts: true,
        unembedComplexFonts: true,
        unembedUnusualFonts: false,
        flatten: true,
      );

      final map = original.toMap();
      final restored = PdfCompressionPreset.fromMap(map);

      expect(restored.jpegQuality, original.jpegQuality);
      expect(restored.colorImageQuality, 72);
      expect(restored.greyImageQuality, 62);
      expect(restored.monoImageQuality, 52);
      expect(restored.deflateStreams, isFalse);
      expect(restored.unembedSimpleFonts, isTrue);
      expect(restored.unembedComplexFonts, isTrue);
      expect(restored.unembedUnusualFonts, isFalse);
      expect(restored.flatten, isTrue);
    });

    test('forQualityFactor differentiates color, grey, and mono presets', () {
      final low = PdfCompressionPreset.forQualityFactor(0.8);
      expect(low.colorImageQuality, 82);
      expect(low.greyImageQuality, 75);
      expect(low.monoImageQuality, 80);

      final med = PdfCompressionPreset.forQualityFactor(0.6);
      expect(med.colorImageQuality, 70);
      expect(med.greyImageQuality, 60);
      expect(med.monoImageQuality, 60);

      final high = PdfCompressionPreset.forQualityFactor(0.35);
      expect(high.colorImageQuality, 58);
      expect(high.greyImageQuality, 48);
      expect(high.monoImageQuality, 45);

      final extreme = PdfCompressionPreset.forQualityFactor(0.15);
      expect(extreme.colorImageQuality, 45);
      expect(extreme.greyImageQuality, 35);
      expect(extreme.monoImageQuality, 30);
    });
  });

  group('PdfCompressionEngine Advanced Features', () {
    test('unembeds embedded fonts when unembed flags are enabled', () async {
      // Build a PDF with an embedded font program stream (FontFile2)
      final dummyFontBytes = Uint8List(512);
      for (var i = 0; i < dummyFontBytes.length; i++) {
        dummyFontBytes[i] = i % 256;
      }
      final fontStream = latin1.decode(dummyFontBytes);

      final pdfBytes = _buildCustomPdf(<String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>',
        '<< /Type /Font /Subtype /TrueType /BaseFont /CustomArial /FontDescriptor 5 0 R >>',
        '<< /Type /FontDescriptor /FontName /CustomArial /FontFile2 6 0 R >>',
        '<< /Length ${dummyFontBytes.length} >>\nstream\n$fontStream\nendstream',
        '<< /Length 40 >>\nstream\nBT /F1 12 Tf (Test) Tj ET\nendstream',
      ]);

      final preset = PdfCompressionPreset(
        jpegQuality: 80,
        maxImageLongSide: 2000,
        maxDecodePixels: 1000000,
        jpegSkipBytesPerPixel: 0.5,
        unembedSimpleFonts: true,
      );

      final output = await PdfCompressionEngine.compressBytes(
        input: pdfBytes,
        preset: preset,
      );

      final outputString = latin1.decode(output);
      expect(outputString.contains('/FontFile2'), isFalse);
    });

    test('flattens optional content groups (layers) when flatten is enabled', () async {
      // Build a PDF with /OCProperties in Catalog and /OC in an image or stream
      final pdfBytes = _buildCustomPdf(<String>[
        '<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [4 0 R] >> >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Resources << /Properties << /Layer1 4 0 R >> >> /Contents 5 0 R >>',
        '<< /Type /OCG /Name (Layer 1) >>',
        '<< /Length 50 /OC 4 0 R >>\nstream\n/OC /Layer1 BDC\nET\nEMC\nendstream',
      ]);

      final preset = PdfCompressionPreset(
        jpegQuality: 80,
        maxImageLongSide: 2000,
        maxDecodePixels: 1000000,
        jpegSkipBytesPerPixel: 0.5,
        flatten: true,
      );

      final output = await PdfCompressionEngine.compressBytes(
        input: pdfBytes,
        preset: preset,
      );

      final outputString = latin1.decode(output);
      expect(outputString.contains('/OCProperties'), isFalse);
    });

    test('compresses 1-bit monochrome image with mono image pipeline', () async {
      const width = 120;
      const height = 120;
      final monoImg = img.Image(width: width, height: height, numChannels: 1);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          monoImg.setPixelRgb(x, y, (x + y) % 2 == 0 ? 0 : 255, 0, 0);
        }
      }
      final pngBytes = Uint8List.fromList(img.encodePng(monoImg));

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Center(
            child: pw.Image(pw.MemoryImage(pngBytes)),
          ),
        ),
      );
      final pdfBytes = Uint8List.fromList(await doc.save());

      final preset = PdfCompressionPreset(
        jpegQuality: 70,
        colorImageQuality: 70,
        greyImageQuality: 60,
        monoImageQuality: 50,
        maxImageLongSide: 100,
        maxDecodePixels: 1000000,
        jpegSkipBytesPerPixel: 0.5,
      );

      final output = await PdfCompressionEngine.compressBytes(
        input: pdfBytes,
        preset: preset,
      );

      expect(output.length, lessThanOrEqualTo(pdfBytes.length));
    });
  });

  group('PdfCompressState & Notifier', () {
    test('notifier updates level and cascades defaults to quality sliders', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pdfCompressProvider.notifier);

      // Default is medium
      var state = container.read(pdfCompressProvider);
      expect(state.compressionLevel, CompressionLevel.medium);
      expect(state.colorImageQuality, 70);
      expect(state.greyImageQuality, 60);
      expect(state.monoImageQuality, 60);

      // Switch to low
      notifier.setCompressionLevel(CompressionLevel.low);
      state = container.read(pdfCompressProvider);
      expect(state.compressionLevel, CompressionLevel.low);
      expect(state.colorImageQuality, 82);
      expect(state.greyImageQuality, 75);
      expect(state.monoImageQuality, 80);

      // Switch to extreme
      notifier.setCompressionLevel(CompressionLevel.extreme);
      state = container.read(pdfCompressProvider);
      expect(state.compressionLevel, CompressionLevel.extreme);
      expect(state.colorImageQuality, 45);
      expect(state.greyImageQuality, 35);
      expect(state.monoImageQuality, 30);
    });

    test('notifier updates individual parameters and toggles advanced panel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pdfCompressProvider.notifier);

      notifier.setColorImageQuality(90);
      notifier.setGreyImageQuality(80);
      notifier.setMonoImageQuality(70);
      notifier.setCompressStreams(false);
      notifier.setUnembedSimpleFonts(true);
      notifier.setUnembedComplexFonts(true);
      notifier.setUnembedUnusualFonts(true);
      notifier.setFlattenLayers(true);
      notifier.toggleAdvancedExpanded();

      final state = container.read(pdfCompressProvider);
      expect(state.colorImageQuality, 90);
      expect(state.greyImageQuality, 80);
      expect(state.monoImageQuality, 70);
      expect(state.compressStreams, isFalse);
      expect(state.unembedSimpleFonts, isTrue);
      expect(state.unembedComplexFonts, isTrue);
      expect(state.unembedUnusualFonts, isTrue);
      expect(state.flattenLayers, isTrue);
      expect(state.isAdvancedExpanded, isTrue);
    });
  });

  group('CompressionSettingsPanel Widget', () {
    testWidgets('renders presets and expands advanced options with all controls', (tester) async {
      var level = CompressionLevel.medium;
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var colorQuality = 70;
      var greyQuality = 60;
      var monoQuality = 60;
      var compressStreams = true;
      var unembedSimple = false;
      var unembedComplex = false;
      var unembedUnusual = false;
      var flatten = false;
      var isAdvancedExpanded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: CompressionSettingsPanel(
                    level: level,
                    onLevelChanged: (l) => setState(() => level = l),
                    colorQuality: colorQuality,
                    onColorQualityChanged: (q) => setState(() => colorQuality = q),
                    greyQuality: greyQuality,
                    onGreyQualityChanged: (q) => setState(() => greyQuality = q),
                    monoQuality: monoQuality,
                    onMonoQualityChanged: (q) => setState(() => monoQuality = q),
                    compressStreams: compressStreams,
                    onCompressStreamsChanged: (v) => setState(() => compressStreams = v),
                    unembedSimpleFonts: unembedSimple,
                    onUnembedSimpleFontsChanged: (v) => setState(() => unembedSimple = v),
                    unembedComplexFonts: unembedComplex,
                    onUnembedComplexFontsChanged: (v) => setState(() => unembedComplex = v),
                    unembedUnusualFonts: unembedUnusual,
                    onUnembedUnusualFontsChanged: (v) => setState(() => unembedUnusual = v),
                    flattenLayers: flatten,
                    onFlattenLayersChanged: (v) => setState(() => flatten = v),
                    isAdvancedExpanded: isAdvancedExpanded,
                    onToggleAdvanced: () => setState(() => isAdvancedExpanded = !isAdvancedExpanded),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Verify level cards render
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Medium'), findsWidgets);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Extreme'), findsOneWidget);

      // Tap "High" preset card
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(level, CompressionLevel.high);

      // Tap Advanced Options header to expand
      expect(find.text('Advanced Options'), findsOneWidget);
      await tester.tap(find.text('Advanced Options'));
      await tester.pumpAndSettle();

      // Sliders and options should now be visible
      expect(find.text('Color Image Quality'), findsOneWidget);
      expect(find.text('Grey Images Quality'), findsOneWidget);
      expect(find.text('Mono Image Quality'), findsOneWidget);
      expect(find.text('Compress Streams'), findsOneWidget);
      expect(find.text('Unembed Simple Fonts'), findsOneWidget);
      expect(find.text('Unembed Complex Fonts'), findsOneWidget);
      expect(find.text('Unembed Unusual Fonts'), findsOneWidget);
      expect(find.text('Flatten (will remove layers)'), findsOneWidget);

      // Toggle a switch (e.g. Flatten)
      final flattenSwitch = find.ancestor(
        of: find.text('Flatten (will remove layers)'),
        matching: find.byType(InkWell),
      );
      expect(flattenSwitch, findsOneWidget);
      await tester.ensureVisible(flattenSwitch);
      await tester.tap(flattenSwitch);
      await tester.pumpAndSettle();
      expect(flatten, isTrue);

      // Toggle Unembed Simple Fonts
      final unembedSimpleSwitch = find.ancestor(
        of: find.text('Unembed Simple Fonts'),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(unembedSimpleSwitch);
      await tester.tap(unembedSimpleSwitch);
      await tester.pumpAndSettle();
      expect(unembedSimple, isTrue);
    });
  });
}
