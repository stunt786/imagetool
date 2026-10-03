import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/notifiers/document_batch_notifier.dart';
import 'package:pixeltools/features/camera/presentation/screens/document_review_screen.dart';
import 'package:pixeltools/features/camera/services/scanner_capability_service.dart';
import 'package:pixeltools/features/files/presentation/files_screen.dart';
import 'package:pixeltools/features/home/presentation/home_screen.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempRoot, this.docsRoot);

  final String tempRoot;
  final String docsRoot;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsRoot;

  @override
  Future<String?> getTemporaryPath() async => tempRoot;
}

class _AlwaysAvailable implements ScannerCapabilityService {
  @override
  Future<bool> isGoogleDocumentScannerAvailable() async => true;
}

Uint8List _sampleJpg(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(220, 220, 220));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory docsRoot;
  late PathProviderPlatform initialPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_onboarding': true,
    });
    tempRoot = await Directory.systemTemp.createTemp('review_nav_temp_');
    docsRoot = await Directory.systemTemp.createTemp('review_nav_docs_');
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path, docsRoot.path);

    const mlKitChannel = MethodChannel('google_mlkit_document_scanner');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mlKitChannel, (call) async {
      if (call.method == 'vision#startDocumentScanner') {
        throw PlatformException(
          code: 'DocumentScanner',
          message: 'Operation cancelled',
        );
      }
      return null;
    });

    const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permChannel, (call) async {
      return <int, int>{0: 1};
    });
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {}
    try {
      await docsRoot.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('Save PDF finishes cleanly and allows subsequent tool & settings navigation without freeze', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            const AppSettingsState(
              savePath: '/dummy',
              isLoading: false,
              hasCompletedOnboarding: true,
            ),
          ),
        ),
      ],
    );
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeScreen), findsOneWidget);

    // Set up a scanned page in documentBatchProvider
    final bytes = _sampleJpg(100, 100);
    final sampleFile = File('${tempRoot.path}/test_page.jpg');
    sampleFile.writeAsBytesSync(bytes);
    await tester.runAsync(() async {
      await container.read(documentBatchProvider.notifier).startNewBatch();
    });
    container.read(documentBatchProvider.notifier).addPage(
      ScannedPage(
        path: sampleFile.path,
        name: 'test_page.jpg',
        sizeBytes: bytes.length,
        imageBytes: bytes,
        width: 100,
        height: 100,
      ),
    );

    // Navigate to /camera/review
    router.push('/camera/review');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DocumentReviewScreen), findsOneWidget);

    // Tap Done button in review top bar to open export sheet
    final doneFinder = find.widgetWithText(TextButton, 'Done');
    expect(doneFinder, findsOneWidget);
    await tester.tap(doneFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap 'Save PDF'
    final savePdfFinder = find.text('Save PDF');
    expect(savePdfFinder, findsOneWidget);
    await tester.tap(savePdfFinder);

    for (var i = 0; i < 80 && router.state.uri.path == '/camera/review'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // App should be cleanly back on HomeScreen
    expect(router.state.uri.path, '/tools');
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    // Verify tools can be tapped and navigated without freeze
    final resizeFinder = find.text('Resize');
    expect(resizeFinder, findsOneWidget);
    await tester.tap(resizeFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(router.state.uri.path, '/images/resizer');

    // Go back to home
    router.go('/tools');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap settings and verify it navigates
    final settingsFinder = find.byIcon(Icons.settings_outlined);
    expect(settingsFinder, findsOneWidget);
    await tester.tap(settingsFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.state.uri.path, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Done button (keep in files) finishes cleanly to /pdfs and allows subsequent navigation', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            const AppSettingsState(
              savePath: '/dummy',
              isLoading: false,
              hasCompletedOnboarding: true,
            ),
          ),
        ),
      ],
    );
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeScreen), findsOneWidget);

    // Set up a scanned page in documentBatchProvider
    final bytes = _sampleJpg(100, 100);
    final sampleFile = File('${tempRoot.path}/test_page_2.jpg');
    sampleFile.writeAsBytesSync(bytes);
    await tester.runAsync(() async {
      await container.read(documentBatchProvider.notifier).startNewBatch();
    });
    container.read(documentBatchProvider.notifier).addPage(
      ScannedPage(
        path: sampleFile.path,
        name: 'test_page_2.jpg',
        sizeBytes: bytes.length,
        imageBytes: bytes,
        width: 100,
        height: 100,
      ),
    );

    // Navigate to /camera/review
    router.push('/camera/review');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DocumentReviewScreen), findsOneWidget);

    // Tap Done button in review to open export sheet
    final doneFinder = find.widgetWithText(TextButton, 'Done');
    expect(doneFinder, findsOneWidget);
    await tester.tap(doneFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // In export sheet, tap 'Done' (keep in files)
    final keepDoneFinder = find.byIcon(Icons.check_circle_outline);
    expect(keepDoneFinder, findsOneWidget);
    await tester.tap(keepDoneFinder);

    for (var i = 0; i < 80 && router.state.uri.path == '/camera/review'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // App should be on FilesScreen (/pdfs)
    expect(router.state.uri.path, '/pdfs');
    expect(find.byType(FilesScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    // Navigate back to /tools
    router.go('/tools');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(HomeScreen), findsOneWidget);

    // Verify settings still functional
    final settingsFinder = find.byIcon(Icons.settings_outlined);
    expect(settingsFinder, findsOneWidget);
    await tester.tap(settingsFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(router.state.uri.path, '/settings');
  });
}
