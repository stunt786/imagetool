import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/operation_store_provider.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/image_to_pdf/models/image_to_pdf_state.dart';
import 'package:pixeltools/features/image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Waits until [predicate] is true or the timeout expires.
Future<void> waitFor(
  ProviderContainer container,
  bool Function(ImageToPdfState state) predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate(container.read(imageToPdfProvider))) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Timed out waiting for state: '
      '${container.read(imageToPdfProvider)}');
}

void main() {
  late Directory tempDir;
  late OperationStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('itp_test_');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = OperationStore(baseDirectoryProvider: () async => tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            AppSettingsState(
              savePath: tempDir.path,
              hasCompletedOnboarding: true,
            ),
          ),
        ),
        operationStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<String>> writeImages(int count, {int size = 240}) async {
    final paths = <String>[];
    for (var i = 0; i < count; i++) {
      final image = img.Image(width: size + i * 8, height: size);
      img.fill(image, color: img.ColorRgb8(30 * i, 120, 210));
      final path = '${tempDir.path}/image_$i.jpg';
      File(path).writeAsBytesSync(
        Uint8List.fromList(img.encodeJpg(image, quality: 85)),
      );
      paths.add(path);
    }
    return paths;
  }

  group('ImageToPdfNotifier', () {
    test('registers images immediately and loads previews progressively',
        () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(5);

      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }

      // The items are visible straight away, before previews exist.
      expect(container.read(imageToPdfProvider).images.length, 5);
      expect(container.read(imageToPdfProvider).isLoadingImages, isTrue);

      await waitFor(container, (state) => !state.isLoadingImages);

      final state = container.read(imageToPdfProvider);
      expect(state.loadedCount, 5);
      expect(state.loadProgress, 100);
      for (final item in state.images) {
        expect(item.previewBytes, isNotNull);
        expect(item.width, isNotNull);
        expect(item.height, isNotNull);
        expect(item.errorMessage, isNull);
      }
      // Previews are downscaled and decodable.
      final preview = img.decodeImage(state.images.first.previewBytes!);
      expect(preview, isNotNull);
      expect(preview!.width, lessThanOrEqualTo(320));
      expect(preview.height, lessThanOrEqualTo(320));
    });

    test('generates a multi-page PDF and reports real progress', () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(3);

      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }
      await waitFor(container, (state) => !state.isLoadingImages);

      final statuses = <String>[];
      container.listen(imageToPdfProvider, (previous, next) {
        final text = next.statusText;
        if (text != null && (statuses.isEmpty || statuses.last != text)) {
          statuses.add(text);
        }
      });

      final outputPath = await notifier.generatePdf();

      expect(outputPath, isNotNull);
      final output = File(outputPath!);
      expect(await output.exists(), isTrue);

      final bytes = await output.readAsBytes();
      expect(utf8.decode(bytes.take(4).toList()), '%PDF');

      final document = syncfusion.PdfDocument(inputBytes: bytes);
      try {
        expect(document.pages.count, 3);
      } finally {
        document.dispose();
      }

      final state = container.read(imageToPdfProvider);
      expect(state.isGenerating, isFalse);
      expect(state.progress, 1.0);
      expect(state.generatedPdfPath, outputPath);
      expect(state.errorMessage, isNull);
      expect(statuses.any((s) => s.startsWith('Adding image')), isTrue);

      // The run is recorded as one operation so Files can group its output.
      expect(store.operationCount, 1);
      final operation = store.operations.single;
      expect(operation.kind, OperationKind.imageToPdf);
      expect(operation.status, OperationStatus.completed);
      expect(operation.itemCount, 1);
      final recorded = store.filesFor(operation.id).single;
      expect(recorded.isPdf, isTrue);
      expect(recorded.pageCount, 3);
      expect(outputPath, startsWith(operation.directoryPath));
      expect(File(recorded.path).existsSync(), isTrue);
    });

    test('a cancelled run is recorded as cancelled, not completed', () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(4);

      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }
      await waitFor(container, (state) => !state.isLoadingImages);

      container.listen(imageToPdfProvider, (previous, next) {
        if (next.isGenerating &&
            (next.statusText ?? '').startsWith('Adding image')) {
          notifier.cancelGeneration();
        }
      });

      expect(await notifier.generatePdf(), isNull);
      expect(store.operationCount, 1);
      expect(store.operations.single.status, OperationStatus.cancelled);
    });

    test('ignores unreadable files without failing the whole build', () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(2);

      // A path that does not exist must not break the queue.
      await notifier.addImageFromPath('${tempDir.path}/missing.jpg');
      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }
      await waitFor(container, (state) => !state.isLoadingImages);

      final state = container.read(imageToPdfProvider);
      expect(state.images.length, 3);
      final broken = state.images.firstWhere(
        (item) => item.name.contains('missing'),
      );
      expect(broken.errorMessage, isNotNull);

      final outputPath = await notifier.generatePdf();
      expect(outputPath, isNotNull);
      final document =
          syncfusion.PdfDocument(inputBytes: await File(outputPath!).readAsBytes());
      try {
        expect(document.pages.count, 2);
      } finally {
        document.dispose();
      }
    });

    test('cancel stops the build before anything is written', () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(4);

      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }
      await waitFor(container, (state) => !state.isLoadingImages);

      // Cancelling before the run starts has no effect, so cancel from within
      // the first status update instead.
      container.listen(imageToPdfProvider, (previous, next) {
        if (next.statusText != null &&
            next.statusText!.startsWith('Adding image') &&
            next.isGenerating) {
          notifier.cancelGeneration();
        }
      });

      final outputPath = await notifier.generatePdf();
      expect(outputPath, isNull);
      final state = container.read(imageToPdfProvider);
      expect(state.isGenerating, isFalse);
      expect(state.statusText, 'Cancelled');
      // No stray PDFs were produced.
      final pdfs = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList();
      expect(pdfs, isEmpty);
    });

    test('reorder and remove update the queue', () async {
      final container = makeContainer();
      final notifier = container.read(imageToPdfProvider.notifier);
      final paths = await writeImages(3);

      for (final path in paths) {
        await notifier.addImageFromPath(path);
      }
      await waitFor(container, (state) => !state.isLoadingImages);

      final before = container.read(imageToPdfProvider).images;
      notifier.reorderImages(0, 3);
      final reordered = container.read(imageToPdfProvider).images;
      expect(reordered.last.id, before.first.id);

      notifier.removeImage(0);
      expect(container.read(imageToPdfProvider).images.length, 2);
    });
  });

  group('PdfPageSettings', () {
    test('copyWith keeps unspecified values', () {
      const settings = PdfPageSettings.defaults;
      final updated = settings.copyWith(pageSize: PdfPageSize.a4);
      expect(updated.pageSize, PdfPageSize.a4);
      expect(updated.orientation, settings.orientation);
      expect(updated.fitMode, settings.fitMode);
      expect(updated.marginLeft, settings.marginLeft);
    });
  });
}
