// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/notifiers/document_batch_notifier.dart';
import 'package:pixeltools/features/camera/presentation/screens/document_filter_screen.dart';
import 'package:pixeltools/features/camera/presentation/screens/magic_remove_screen.dart';
import 'package:pixeltools/features/camera/presentation/screens/perspective_correction_screen.dart';
import 'package:pixeltools/features/camera/presentation/widgets/document_corners_painter.dart';
import 'package:pixeltools/features/camera/presentation/widgets/document_scanner_overlay.dart';
import 'package:pixeltools/features/camera/presentation/widgets/enhance_filters_sheet.dart';
import 'package:pixeltools/features/camera/presentation/widgets/post_capture_menu.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/camera/services/batch_storage_service.dart';
import 'package:pixeltools/shared/notifiers/edit_history_notifier.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
}

Uint8List makeJpg(int w, int h, {int r = 240, int g = 240, int b = 240}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late PathProviderPlatform original;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('scratch2_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(temp.path);
    Directory('${temp.path}/tmp').createSync(recursive: true);
    Directory('${temp.path}/docs').createSync(recursive: true);
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('painter rasterizes', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = DocumentCornersPainter(
      corners: const [
        Offset(50, 50),
        Offset(150, 50),
        Offset(150, 150),
        Offset(50, 150),
      ],
      showOverlay: true,
    );
    painter.paint(canvas, const Size(200, 200));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(200, 200);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    print('bytes=${data?.lengthInBytes}');
    int px(int x, int y) {
      final o = (y * 200 + x) * 4;
      return data!.getUint8(o);
    }

    int alpha(int x, int y) {
      final o = (y * 200 + x) * 4;
      return data!.getUint8(o + 3);
    }

    print('outside(10,10)=${px(10, 10)},${px(10, 10 + 0)}, alpha=${alpha( 10, 10)}');
    // Read rgba at (10,10) fully
    final o = (10 * 200 + 10) * 4;
    print('rgba outside= ${data!.getUint8(o)},${data.getUint8(o + 1)},${data.getUint8(o + 2)},${data.getUint8(o + 3)}');
    final oi = (100 * 200 + 100) * 4;
    print('rgba inside= ${data.getUint8(oi)},${data.getUint8(oi + 1)},${data.getUint8(oi + 2)},${data.getUint8(oi + 3)}');
    final oc = (50 * 200 + 50) * 4;
    print('rgba corner= ${data.getUint8(oc)},${data.getUint8(oc + 1)},${data.getUint8(oc + 2)},${data.getUint8(oc + 3)}');
    // shouldRepaint
    final p2 = DocumentCornersPainter(
        corners: const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(150, 150),
          Offset(50, 150),
        ],
        showOverlay: true);
    print('shouldRepaint new list instance: ${p2.shouldRepaint(painter)}');
    print('shouldRepaint same instance: ${painter.shouldRepaint(painter)}');
    final p3 = DocumentCornersPainter(
        corners: painter.corners, showOverlay: false);
    print('shouldRepaint overlay toggle: ${p3.shouldRepaint(painter)}');
    // 3 corners: no throw
    final p4 = DocumentCornersPainter(corners: const [Offset(1, 1)]);
    expect(() => p4.paint(Canvas(ui.PictureRecorder()), const Size(50, 50)),
        returnsNormally);
  });

  testWidgets('overlay renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentScannerOverlay(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Align document within frame'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentScannerOverlay(
          isDocumentDetected: true,
          autoCaptureProgress: 0.5,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Document detected'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentScannerOverlay(
          isDocumentDetected: true,
          autoCaptureProgress: 0.5,
          isAutoCaptureEnabled: false,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('enhance sheet renders and applies', (tester) async {
    final sw = Stopwatch()..start();
    void mark(String m) => print('[enh] ${sw.elapsedMilliseconds}ms $m');
    mark('start');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final page = ScannedPage(
      path: '',
      name: 'a.jpg',
      sizeBytes: 10,
      imageBytes: makeJpg(60, 60),
    );
    container.read(documentBatchProvider.notifier).addPage(page);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EnhanceFiltersSheet(pageIndex: 0))),
    ));
    await tester.pump();
    mark('pumped');
    expect(find.text('Enhance'), findsWidgets); // header + filter tile
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Magic color'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);

    // selection state
    Text originalLabel =
        tester.widget<Text>(find.descendant(of: find.widgetWithText(InkWell, 'Original'), matching: find.byType(Text)));
    print('original weight=${originalLabel.style?.fontWeight}');
    mark('before magic tap');
    await tester.tap(find.widgetWithText(InkWell, 'Magic color'));
    mark('magic tapped');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    mark('magic pumped');
    Text magicLabel = tester
        .widget<Text>(find.descendant(of: find.widgetWithText(InkWell, 'Magic color'), matching: find.byType(Text)));
    print('magic weight=${magicLabel.style?.fontWeight}');

    // apply with Original (none) -> pops
    await tester.tap(find.widgetWithText(InkWell, 'Original'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    mark('apply tapped');
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    mark('apply done');
    print('sheet still present: ${find.byType(EnhanceFiltersSheet).evaluate().length}');
    print('page state: ${container.read(documentBatchProvider).pages.first.filterType}');
    print('batch dir: ${container.read(documentBatchProvider).batchDirectory}');
  });

  testWidgets('enhance sheet empty page', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(body: EnhanceFiltersSheet(pageIndex: 5))),
    ));
    await tester.pump();
    expect(find.text('No page to enhance'), findsOneWidget);
  });

  testWidgets('post capture menu', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final imgFile = File('${temp.path}/shot.jpg')..writeAsBytesSync(makeJpg(80, 80));
    var retakes = 0;
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: PostCaptureMenu(
              imagePath: imgFile.path,
              isDocumentMode: true,
              onRetake: () => retakes++,
            ),
          ),
        ),
        GoRoute(path: '/camera/filter', builder: (c, s) => const Text('filter screen')),
        GoRoute(path: '/images/resizer', builder: (c, s) => const Text('resizer')),
        GoRoute(path: '/images/convert', builder: (c, s) => const Text('convert')),
        GoRoute(path: '/images/to-pdf', builder: (c, s) => const Text('pdf')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pump();
    expect(find.text('Next Steps'), findsOneWidget);
    expect(find.text('Apply Filters'), findsOneWidget);
    expect(find.text('Convert to PDF'), findsOneWidget);
    expect(find.text('Resize or Compress'), findsOneWidget);
    expect(find.text('Magic Remove'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Retake'));
    await tester.pump();
    print('retakes=$retakes');

    await tester.tap(find.text('Apply Filters'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    print('route=${router.routerDelegate.currentConfiguration.uri}');
    print('pages=${container.read(documentBatchProvider).pages.length}');
    print('batchId=${container.read(documentBatchProvider.notifier).batchId}');
  });

  testWidgets('post capture photo mode', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final imgFile = File('${temp.path}/shot2.jpg')..writeAsBytesSync(makeJpg(80, 80));
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: PostCaptureMenu(
            imagePath: imgFile.path,
            isDocumentMode: false,
            onRetake: () {},
          ),
        ),
      ),
      GoRoute(path: '/images/resizer', builder: (c, s) => const Text('resizer')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pump();
    expect(find.text('Resize & Edit'), findsOneWidget);
    expect(find.text('Format Change'), findsOneWidget);
    expect(find.text('Apply Filters'), findsNothing);
    await tester.tap(find.text('Resize & Edit'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
    }
    print('photo route=${router.routerDelegate.currentConfiguration.uri}');
  });

  testWidgets('document filter screen', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final page = ScannedPage(
      path: '',
      name: 'a.jpg',
      sizeBytes: 10,
      imageBytes: makeJpg(60, 60),
    );
    container.read(documentBatchProvider.notifier).addPage(page);

    final router = GoRouter(initialLocation: '/camera/filter', routes: [
      GoRoute(path: '/camera/filter', builder: (c, s) => const DocumentFilterScreen()),
      GoRoute(path: '/home', builder: (c, s) => const Text('home')),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Edit Page'), findsOneWidget);
    expect(find.text('Select Filter'), findsOneWidget);
    expect(find.text('Apply Filter'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Lighten'), findsOneWidget);
    final scrollable = find.byType(Scrollable);
    await tester.scrollUntilVisible(find.text('Binarize'), 200,
        scrollable: scrollable);
    expect(find.text('Binarize'), findsOneWidget);

    // apply to all with empty batch
    final emptyContainer = ProviderContainer();
    addTearDown(emptyContainer.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: emptyContainer, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('No pages to filter'), findsOneWidget);
  });

  testWidgets('perspective screen no page', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/camera/perspective', routes: [
      GoRoute(path: '/camera/perspective', builder: (c, s) => const PerspectiveCorrectionScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('No page selected'), findsOneWidget);
    expect(find.text('Perspective Correction'), findsOneWidget);
  });

  testWidgets('perspective screen with page', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final page = ScannedPage(path: '', name: 'a.jpg', sizeBytes: 10, imageBytes: makeJpg(200, 150));
    container.read(documentBatchProvider.notifier).addPage(page);

    final router = GoRouter(initialLocation: '/camera/perspective', routes: [
      GoRoute(path: '/camera/perspective', builder: (c, s) {
        return const PerspectiveCorrectionScreen();
      }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    // Can't pass extra via go() easily after pump; use go with extra before pump
    router.go('/camera/perspective', extra: 0);
    await tester.pumpAndSettle();
    expect(find.text('Crop & Perspective'), findsOneWidget);
    expect(find.text('Auto Fit'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Apply Crop'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('magic remove screen', (tester) async {
    final sw = Stopwatch()..start();
    void mark(String m) => print('[mm] ${sw.elapsedMilliseconds}ms $m');
    mark('start');
    final bytes = makeJpg(120, 120);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MagicRemoveScreen(imageBytes: bytes)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Magic Remove'), findsOneWidget);
    expect(find.text('Brush'), findsOneWidget);
    expect(find.text('Draw to select'), findsOneWidget);
    expect(find.text('Auto-detect'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    print('slider=${slider.value}');

    mark('rendered');
    await tester.tap(find.widgetWithText(GestureDetector, 'XL'));
    await tester.pump(const Duration(milliseconds: 200));
    mark('xl tapped');
    print('slider after XL=${tester.widget<Slider>(find.byType(Slider)).value}');

    // draw a stroke on the canvas
    final canvasFinder = find.descendant(
        of: find.byType(AspectRatio), matching: find.byType(GestureDetector));
    print('gesture detectors=${canvasFinder.evaluate().length}');
    final center = tester.getCenter(find.byType(AspectRatio));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(center + const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    mark('stroke drawn');
    expect(find.text('1 stroke'), findsOneWidget);
    expect(find.text('Erase (1)'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, 'Clear'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('1 stroke'), findsNothing);

    // redraw and erase
    final g2 = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 50));
    await g2.moveTo(center + const Offset(30, 10));
    await tester.pump(const Duration(milliseconds: 50));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Erase (1)'), findsOneWidget);

    await tester.tap(find.text('Erase (1)'));
    mark('erase tapped');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Analyzing and removing...'), findsOneWidget);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    mark('erase finished');
    expect(find.text('Object erased'), findsOneWidget);
    expect(find.text('Draw to select'), findsOneWidget);
    print('stroke badge after erase: ${find.text('1 stroke').evaluate().length}');
  });

  test('notifier flows', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(documentBatchProvider.notifier);

    print('initial batchId=${notifier.batchId}');
    await notifier.startNewBatch();
    final batchDir = container.read(documentBatchProvider).batchDirectory;
    print('batchDir=$batchDir exists=${Directory(batchDir!).existsSync()}');
    print('batchId=${notifier.batchId}');

    final src = File('${temp.path}/src.jpg')..writeAsBytesSync(makeJpg(80, 80));
    await notifier.addPageFromPath(src.path);
    final b1 = container.read(documentBatchProvider);
    print('pages=${b1.pages.length} path=${b1.pages.first.path}');
    print('file exists=${File(b1.pages.first.path).existsSync()}');
    print('undoDepth=${b1.undoDepth} canUndo=${notifier.canUndo}');

    await notifier.removePage(0);
    final b2 = container.read(documentBatchProvider);
    print('after remove pages=${b2.pages.length} undoDepth=${b2.undoDepth}');
    print('removed file exists=${File(b1.pages.first.path).existsSync()}');
    notifier.undo();
    final b3 = container.read(documentBatchProvider);
    print('after undo pages=${b3.pages.length} redoDepth=${b3.redoDepth}');

    // watermark export
    final off = const AppSettingsState(savePath: '', enableGlobalWatermark: false);
    final on = const AppSettingsState(savePath: '', enableGlobalWatermark: true);
    final expOff = notifier.getExportPageBytes(0, off);
    final expOn = notifier.getExportPageBytes(0, on);
    print('export off len=${expOff.length} same=${_eq(expOff, container.read(documentBatchProvider).pages.first.displayBytes)}');
    print('export on len=${expOn.length} same=${_eq(expOff, expOn)}');
    final onDecoded = img.decodeImage(expOn);
    print('on decoded=${onDecoded?.width}x${onDecoded?.height}');
    print('out of range=${notifier.getExportPageBytes(9, off).length}');
    print('all=${notifier.getAllExportPageBytes(off).length}');

    // edit history through filter apply
    SharedPreferences.setMockInitialValues({});
    await notifier.applyFilterToPage(0, FilterType.grayscale);
    final after = container.read(documentBatchProvider);
    print('filterType=${after.pages.first.filterType} filtered=${after.pages.first.filteredBytes != null}');
    print('width=${after.pages.first.width} height=${after.pages.first.height}');
    final hist = container.read(editHistoryProvider);
    print('history=${hist.map((e) => e.fileName).toList()}');

    await notifier.clearBatch();
    final b4 = container.read(documentBatchProvider);
    print('after clear id="${b4.id}" pages=${b4.pages.length} undoDepth=${b4.undoDepth}');
    print('batch dir exists=${Directory(batchDir).existsSync()}');
  });

  test('batch storage corner cases', () async {
    // late mtime cleanup
    final root = Directory('${temp.path}/tmp/temp_scans')..createSync(recursive: true);
    final old = Directory('${root.path}/old_batch')..createSync();
    File('${old.path}/page_0.jpg').writeAsBytesSync([1, 2, 3]);
    final touch = Process.runSync('touch', ['-d', '2 days ago', old.path]);
    print('touch exit=${touch.exitCode} err=${touch.stderr}');
    final active = Directory('${root.path}/active_batch')..createSync();
    Process.runSync('touch', ['-d', '2 days ago', active.path]);
    final fresh = Directory('${root.path}/fresh_batch')..createSync();

    await _cleanOrphaned({'active_batch'});
    print('old exists=${old.existsSync()} active=${active.existsSync()} fresh=${fresh.existsSync()}');
  });
}

Future<void> _cleanOrphaned(Set<String> ids) {
  return BatchStorageService.cleanOrphanedBatches(ids);
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
