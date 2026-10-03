import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

import 'package:pixeltools/core/services/pdf_service.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';
import 'package:pixeltools/shared/services/watermark_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List iconBytes;

  setUpAll(() {
    final iconFile = File('assets/icons/icon.png');
    expect(iconFile.existsSync(), isTrue, reason: 'assets/icons/icon.png must exist');
    iconBytes = iconFile.readAsBytesSync();
    WatermarkHelper.setIconBytes(iconBytes);
  });

  group('AppSettings Defaults & State', () {
    test('Watermark defaults match specifications', () {
      const settings = AppSettingsState(savePath: '/test/path');
      expect(settings.enableGlobalWatermark, isTrue);
      expect(settings.useWatermarkLogo, isTrue);
      expect(settings.watermarkText, equals('PixelTools'));
      expect(settings.watermarkColorHex, equals(0xFF2196F3));
      expect(settings.watermarkOpacity, equals(0.7));
      expect(settings.watermarkPositionIndex, equals(4)); // Bottom-Right
      expect(settings.watermarkColor, equals(0xFF2196F3));
      expect(settings.watermarkPosition, equals(4));
    });

    test('Migration from old default "◈ PixelTools" to "PixelTools"', () async {
      SharedPreferences.setMockInitialValues({
        'watermark_text': '◈ PixelTools',
      });
      final text = await AppSettingsState.loadWatermarkText();
      expect(text, equals('PixelTools'));
    });

    test('Use watermark logo persistence', () async {
      SharedPreferences.setMockInitialValues({
        'use_watermark_logo': false,
      });
      final val = await AppSettingsState.loadUseWatermarkLogo();
      expect(val, isFalse);
    });

    test('Use image vertical sidebar persistence', () async {
      SharedPreferences.setMockInitialValues({
        'use_image_vertical_sidebar': false,
      });
      final val = await AppSettingsState.loadUseImageVerticalSidebar();
      expect(val, isFalse);
    });
  });

  group('WatermarkHelper & PDF Widgets', () {
    test('applyToImage with icon logo and PixelTools text', () {
      const settings = AppSettingsState(
        savePath: '/test',
        useWatermarkLogo: true,
        watermarkText: 'PixelTools',
        useImageVerticalSidebar: false,
      );

      final image = img.Image(width: 200, height: 200);
      img.fill(image, color: img.ColorRgb8(50, 50, 50));

      final output = WatermarkHelper.applyToImage(image, settings);
      expect(output.width, equals(200));
      expect(output.height, equals(200));
    });

    test('applyRightVerticalSidebar places watermark along right edge with low opacity', () {
      const settings = AppSettingsState(
        savePath: '/test',
        useWatermarkLogo: true,
        watermarkText: 'PixelTools',
        useImageVerticalSidebar: true,
        watermarkOpacity: 0.7,
      );

      final image = img.Image(width: 500, height: 500);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final output = WatermarkHelper.applyRightVerticalSidebar(
        image,
        settings,
        iconBytes: iconBytes,
      );

      expect(output.width, equals(500));
      expect(output.height, equals(500));

      // Far left pixels should remain untouched black
      final leftPixel = output.getPixel(20, 250);
      expect(leftPixel.r, equals(0));
      expect(leftPixel.g, equals(0));
      expect(leftPixel.b, equals(0));

      // Pixels along the right margin (x near 470, y near 250) should be modified by the vertical strip
      bool rightAreaModified = false;
      for (int x = 400; x < 500; x++) {
        for (int y = 200; y < 300; y++) {
          final p = output.getPixel(x, y);
          if (p.r > 0 || p.g > 0 || p.b > 0) {
            rightAreaModified = true;
            break;
          }
        }
        if (rightAreaModified) break;
      }
      expect(rightAreaModified, isTrue);
    });

    test('applyGlobalWatermarkIfNeeded applies right vertical sidebar by default', () {
      const settings = AppSettingsState(
        savePath: '/test',
        enableGlobalWatermark: true,
        useWatermarkLogo: true,
        watermarkText: 'PixelTools',
      );

      final image = img.Image(width: 300, height: 300);
      img.fill(image, color: img.ColorRgb8(20, 20, 20));
      final rawPng = Uint8List.fromList(img.encodePng(image));

      final resultBytes = WatermarkHelper.applyGlobalWatermarkIfNeeded(
        rawPng,
        settings,
        iconBytes: iconBytes,
      );

      expect(resultBytes.isNotEmpty, isTrue);
      final decoded = img.decodePng(resultBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(300));
      expect(decoded.height, equals(300));
    });

    test('Watermark has no background color (plain color watermark)', () {
      const settings = AppSettingsState(
        savePath: '/test',
        useWatermarkLogo: false,
        watermarkText: 'PixelTools',
        useImageVerticalSidebar: true,
        watermarkColorHex: 0xFFFFFFFF,
      );

      // On a pure blue canvas (0, 0, 255)
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(0, 0, 255));

      final output = WatermarkHelper.applyRightVerticalSidebar(
        image,
        settings,
      );

      // Transparent background means areas around characters remain pure blue
      int pureBlueCountInRightStrip = 0;
      for (int x = 360; x < 400; x++) {
        for (int y = 150; y < 250; y++) {
          final p = output.getPixel(x, y);
          if (p.r == 0 && p.g == 0 && p.b == 255) {
            pureBlueCountInRightStrip++;
          }
        }
      }
      expect(pureBlueCountInRightStrip > 100, isTrue);
    });

    test('buildPdfWatermarkWidget builds pw.Widget successfully', () async {
      final widget = WatermarkHelper.buildPdfWatermarkWidget(
        iconBytes: iconBytes,
        text: 'PixelTools',
        colorHex: 0xFFFFFFFF,
        opacity: 0.7,
        positionIndex: 4,
        useAppLogo: true,
      );

      expect(widget, isNotNull);

      // Verify rendering inside a pw.Document
      final pdfDoc = pw.Document();
      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Stack(
            children: [
              pw.Center(child: pw.Text('Sample Page')),
              widget,
            ],
          ),
        ),
      );

      final pdfBytes = await pdfDoc.save();
      expect(pdfBytes.isNotEmpty, isTrue);
    });
  });

  group('Syncfusion PDF Service Watermarking', () {
    test('PdfService.applyWatermarkToSyncfusionPage renders watermark with icon', () {
      final document = syncfusion.PdfDocument();
      final page = document.pages.add();

      PdfService.applyWatermarkToSyncfusionPage(
        page,
        iconBytes: iconBytes,
        text: 'PixelTools',
        colorHex: 0xFFFFFFFF,
        opacity: 0.7,
        positionIndex: 4,
        useAppLogo: true,
      );

      final bytes = document.saveSync();
      document.dispose();

      expect(bytes.isNotEmpty, isTrue);
      // Valid PDF starts with %PDF
      final header = String.fromCharCodes(bytes.take(4));
      expect(header, equals('%PDF'));
    });

    test('PdfService.isolateCompressWorker applies watermark by default', () async {
      final doc = syncfusion.PdfDocument();
      doc.pages.add();
      final inputBytes = doc.saveSync();
      doc.dispose();

      final result = await PdfService.isolateCompressWorker({
        'inputBytes': Uint8List.fromList(inputBytes),
        'quality': 0.8,
        'applyWatermark': true,
        'watermarkText': 'PixelTools',
        'watermarkPosition': 4,
        'watermarkOpacity': 0.7,
        'watermarkColor': 0xFFFFFFFF,
        'useWatermarkLogo': true,
        'iconBytes': iconBytes,
      });

      expect(result.isNotEmpty, isTrue);
    });
  });

  group('SettingsScreen UI', () {
    testWidgets('SettingsScreen displays Live Preview, Include App Logo, and Vertical Sidebar toggle',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({
        'enable_global_watermark': true,
        'use_watermark_logo': true,
        'use_image_vertical_sidebar': true,
        'watermark_text': 'PixelTools',
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Global Watermark switch exists
      expect(find.text('Global Watermark'), findsOneWidget);

      // Verify Include App Logo switch exists
      expect(find.text('Include App Logo'), findsOneWidget);

      // Verify Right Vertical Sidebar switch exists
      expect(find.text('Right Vertical Sidebar for Images'), findsOneWidget);

      // Verify Live Preview title and segments exist
      expect(find.text('Live Preview'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);

      // Verify default text in TextField is PixelTools
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('PixelTools'));

      // Switch to PDF tab
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('PDF • Corner Watermark'), findsOneWidget);
    });
  });
}
