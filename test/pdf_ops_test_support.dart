// Shared fixtures for the PDF feature tests.
//
// Deliberately NOT named `*_test.dart`: the Flutter test runner only picks up
// files ending in `_test.dart`, so this file is compiled on demand by the
// tests that import it.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/shared/models/picked_file.dart';
import 'package:pixeltools/shared/services/file_picker_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Serves the app-private `documents` and `cache` directories from a temp
/// folder so tests can inspect (and delete) everything the app writes.
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// A [FilePickerService] that replays canned responses instead of opening a
/// real picker dialog, so the notifiers can be driven without a platform.
class FakeFilePickerService extends FilePickerService {
  FakeFilePickerService(Iterable<List<PickedFile>> batches)
      : _batches = List<List<PickedFile>>.of(batches);

  final List<List<PickedFile>> _batches;

  /// Every `pick` call, in order, so tests can assert picker arguments.
  final List<PickTarget> requestedTargets = <PickTarget>[];

  int get remainingBatches => _batches.length;

  @override
  Future<List<PickedFile>> pick({
    required BuildContext context,
    required PickTarget target,
    required bool allowMultiple,
    int? maxAssets,
  }) async {
    requestedTargets.add(target);
    if (_batches.isEmpty) return const <PickedFile>[];
    return _batches.removeAt(0);
  }
}

/// Builds a small but valid PDF. When [text] is given every page carries that
/// string so Syncfusion's text extractor (and therefore the OCR pipeline) has
/// something to read.
Future<Uint8List> buildPdfBytes({
  int pages = 1,
  String? text,
  List<ui.Size>? pageSizes,
}) async {
  final doc = syncfusion.PdfDocument();
  final count = pageSizes?.length ?? pages;
  for (var i = 0; i < count; i++) {
    final section = doc.sections!.add();
    if (pageSizes != null) {
      section.pageSettings.size = pageSizes[i];
      section.pageSettings.margins.all = 0;
    }
    final page = section.pages.add();
    if (text != null) {
      page.graphics.drawString(
        text,
        syncfusion.PdfStandardFont(syncfusion.PdfFontFamily.helvetica, 12),
        bounds: const ui.Rect.fromLTWH(40, 40, 480, 200),
      );
    }
  }
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

/// Writes a PDF built by [buildPdfBytes] into [dir] and returns its path.
Future<String> writePdf(
  Directory dir,
  String name, {
  int pages = 1,
  String? text,
  List<ui.Size>? pageSizes,
}) async {
  final bytes = await buildPdfBytes(pages: pages, text: text, pageSizes: pageSizes);
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// Parses [bytes] with Syncfusion. Callers must [syncfusion.PdfDocument.dispose]
/// the result.
syncfusion.PdfDocument syncfusionDocOf(Uint8List bytes) =>
    syncfusion.PdfDocument(inputBytes: bytes);

/// Parses [bytes] with Syncfusion and returns the page count. Throws for
/// corrupt input.
int pageCountOf(Uint8List bytes) {
  final doc = syncfusion.PdfDocument(inputBytes: bytes);
  try {
    return doc.pages.count;
  } finally {
    doc.dispose();
  }
}

/// A PDF-shaped byte string that is definitely not a parseable document.
Uint8List corruptPdfBytes() =>
    Uint8List.fromList('not a pdf at all'.codeUnits);

/// The pdfx renderer channel. `pdfx` has no desktop implementation, so tests
/// fake it here; see [installPdfxMock].
const MethodChannel kPdfxChannel = MethodChannel('io.scer.pdf_renderer');

/// Installs a fake pdfx renderer that reports [pageCount] pages and renders
/// solid-colour PNG pages sized to the request. Returns the recorded calls.
List<MethodCall> installPdfxMock({required int pageCount}) {
  final log = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kPdfxChannel, (call) async {
    log.add(call);
    switch (call.method) {
      case 'open.document.file':
      case 'open.document.asset':
      case 'open.document.data':
        return <dynamic, dynamic>{'id': 'doc-1', 'pagesCount': pageCount};
      case 'open.page':
        final args = call.arguments as Map<dynamic, dynamic>;
        return <dynamic, dynamic>{
          'id': 'page-${args['page']}',
          'width': 612,
          'height': 792,
        };
      case 'render':
        final args = call.arguments as Map<dynamic, dynamic>;
        final width = (args['width'] as num).toInt().clamp(1, 4096);
        final height = (args['height'] as num).toInt().clamp(1, 4096);
        final image = img.Image(width: width, height: height);
        img.fill(image, color: img.ColorRgb8(10, 120, 200));
        return <dynamic, dynamic>{
          'width': width,
          'height': height,
          'data': Uint8List.fromList(img.encodePng(image)),
        };
      default:
        return null;
    }
  });
  return log;
}

void uninstallPdfxMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kPdfxChannel, null);
}

/// pdfx's `PdfDocument.openFile` calls the async `assertHasPdfSupport()`
/// *without awaiting it*. On Linux the check resolves to "unsupported" a few
/// microtasks later and the stray future completes with an unhandled
/// [PlatformNotSupportedException], which the test framework treats as a
/// failure. Every test that touches pdfx therefore runs its body through
/// [guard], which parks that stray error in [strayError] where the test can
/// assert on it instead of dying on it.
class PdfxZone {
  Object? strayError;

  Future<T> guard<T>(Future<T> Function() body) async {
    final guarded = runZonedGuarded(body, (error, stack) {
      strayError ??= error;
    });
    try {
      return await guarded!;
    } finally {
      // Let the fire-and-forget support check report before the zone dies.
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Pumps a minimal app and returns the `BuildContext` of its scaffold, so
/// notifier APIs that require a context can be driven from widget tests.
Future<BuildContext> pumpContext(
  WidgetTester tester,
  ProviderContainer? container,
) async {
  late BuildContext ctx;
  final Widget child = MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  if (container == null) {
    await tester.pumpWidget(child);
  } else {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: child),
    );
  }
  return ctx;
}
