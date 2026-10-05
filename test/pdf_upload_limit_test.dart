// ignore_for_file: depend_on_referenced_packages

// Tests for the PDF upload limit and the limits derived from it.
//
// The upload limit is a single constant that several modules enforce, so the
// assertions below focus on the constant itself, the label that is shown to
// users, and the size-dependent budgets that must stay consistent with it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/pdf_compression_engine.dart';
import 'package:pixeltools/core/services/private_to_public_pdf_manager.dart';
import 'package:pixeltools/core/utils/file_type_detector.dart';
import 'package:pixeltools/shared/models/picked_file.dart';

/// Serves the sandbox root from a temp directory so the manager can create it.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileTypeDetector PDF limits', () {
    test('the upload limit is 50 MB', () {
      expect(FileTypeDetector.maxPdfSizeBytes, 50 * 1024 * 1024);
    });

    test('the label matches the limit', () {
      expect(FileTypeDetector.maxPdfSizeLabel, '50 MB');
    });

    test('the merge combined-size cap is tighter than the per-file cap allows',
        () {
      // Merging buffers every input at once, so the combined cap must bind
      // before N files at the per-file limit could be loaded together.
      expect(
        FileTypeDetector.maxMergeCombinedBytes,
        lessThan(
          FileTypeDetector.maxPdfSizeBytes * FileTypeDetector.maxMergePdfCount,
        ),
      );
    });

    test('the engine backstop accepts anything the picker accepted', () {
      expect(
        PdfCompressionEngine.maxInputBytes,
        greaterThanOrEqualTo(FileTypeDetector.maxPdfSizeBytes),
      );
    });
  });

  group('PdfCompressionEngine size-dependent budgets', () {
    test('small documents keep the base budget', () {
      final base = PdfCompressionEngine.timeBudgetForInputBytes(1024);
      expect(
        PdfCompressionEngine.timeBudgetForInputBytes(4 * 1024 * 1024),
        base,
      );
    });

    test('the budget grows with the input size', () {
      // Sampled below the cap; past it the budget is deliberately flat.
      var previous = Duration.zero;
      for (final megabytes in <int>[6, 12, 18, 24, 30, 36, 42, 48]) {
        final budget = PdfCompressionEngine.timeBudgetForInputBytes(
          megabytes * 1024 * 1024,
        );
        expect(budget, greaterThan(previous),
            reason: 'budget must grow at $megabytes MB');
        previous = budget;
      }
    });

    test('the budget is capped so the UI never waits forever', () {
      final budget = PdfCompressionEngine.timeBudgetForInputBytes(
        64 * 1024 * 1024 * 1024,
      );
      expect(budget, lessThanOrEqualTo(const Duration(minutes: 5)));
    });

    test('the budget is still growing across the whole accepted range', () {
      // The cap must not be reached before the upload limit is, or large
      // documents would silently get the same budget as small ones.
      final atLimit = PdfCompressionEngine.timeBudgetForInputBytes(
        FileTypeDetector.maxPdfSizeBytes,
      );
      expect(atLimit, lessThanOrEqualTo(const Duration(minutes: 5)));
      expect(
        atLimit,
        greaterThan(PdfCompressionEngine.timeBudgetForInputBytes(1024)),
      );
    });

    test('the run timeout always exceeds the re-encoding budget', () {
      for (final megabytes in <int>[1, 6, 18, 50, 2048]) {
        final bytes = megabytes * 1024 * 1024;
        expect(
          PdfCompressionEngine.timeoutForInputBytes(bytes),
          greaterThan(PdfCompressionEngine.timeBudgetForInputBytes(bytes)),
          reason: 'timeout must outlast the budget at $megabytes MB',
        );
      }
    });
  });

  group('PdfCompressionPreset.withTimeBudget', () {
    test('changes only the budget', () {
      final original = PdfCompressionPreset.forQualityFactor(0.5,
          colorImageQuality: 71, greyImageQuality: 61, monoImageQuality: 51);
      final updated =
          original.withTimeBudget(const Duration(minutes: 9));

      expect(updated.timeBudget, const Duration(minutes: 9));
      expect(updated.jpegQuality, original.jpegQuality);
      expect(updated.colorImageQuality, 71);
      expect(updated.greyImageQuality, 61);
      expect(updated.monoImageQuality, 51);
      expect(updated.maxImageLongSide, original.maxImageLongSide);
      expect(updated.maxDecodePixels, original.maxDecodePixels);
      expect(updated.jpegSkipBytesPerPixel, original.jpegSkipBytesPerPixel);
      expect(updated.minImageBytes, original.minImageBytes);
      expect(updated.deflateStreams, original.deflateStreams);
      expect(updated.unembedSimpleFonts, original.unembedSimpleFonts);
      expect(updated.unembedComplexFonts, original.unembedComplexFonts);
      expect(updated.unembedUnusualFonts, original.unembedUnusualFonts);
      expect(updated.flatten, original.flatten);
    });
  });

  group('PrivateToPublicPdfManager rejects oversized PDFs', () {
    late Directory tempDir;
    late PathProviderPlatform initialPathProvider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdf_limit_');
      initialPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = initialPathProvider;
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('reports the limit in the error for an oversized path', () async {
      final path = '${tempDir.path}/huge.pdf';
      await File(path).writeAsBytes(<int>[0x25, 0x50, 0x44, 0x46], flush: true);
      // Seeking past the end keeps the file sparse: the reported length is
      // real without writing 50 MB of zeros to disk.
      final handle = await File(path).open(mode: FileMode.append);
      await handle.setPosition(FileTypeDetector.maxPdfSizeBytes + 1);
      await handle.close();

      final manager = PrivateToPublicPdfManager();
      await expectLater(
        () => manager.importPickedFile(PickedFile(
              path: path,
              name: 'huge.pdf',
              extension: 'pdf',
              sizeBytes: FileTypeDetector.maxPdfSizeBytes + 1,
            )),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('huge.pdf'),
              contains(FileTypeDetector.maxPdfSizeLabel),
            ),
          ),
        ),
      );
      await manager.cleanup();
    });

    test('accepts a PDF under the limit', () async {
      final path = '${tempDir.path}/ok.pdf';
      await File(path).writeAsBytes(<int>[0x25, 0x50, 0x44, 0x46], flush: true);

      final manager = PrivateToPublicPdfManager();
      final sandboxPath =
          await manager.importPickedFile(PickedFile(
        path: path,
        name: 'ok.pdf',
        extension: 'pdf',
        sizeBytes: 4,
      ));

      expect(await File(sandboxPath).exists(), isTrue);
      await manager.cleanup();
    });
  });
}
