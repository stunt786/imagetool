// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/camera/presentation/camera_screen.dart';
import 'package:pixeltools/features/camera/services/scanner_capability_service.dart';
import 'package:pixeltools/features/files/presentation/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _AlwaysAvailable implements ScannerCapabilityService {
  @override
  Future<bool> isGoogleDocumentScannerAvailable() async => true;
}

void main() {
  const channel = MethodChannel('google_mlkit_document_scanner');
  var scanStarts = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_onboarding': true,
    });
    scanStarts = 0;
    MlKitScannerCapability.resetCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'vision#startDocumentScanner') {
        scanStarts++;
        // The plugin reports the user backing out as a PlatformException.
        throw PlatformException(
          code: 'DocumentScanner',
          message: 'Operation cancelled',
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    MlKitScannerCapability.resetCache();
  });

  testWidgets('the empty history scan button launches the ML Kit scanner',
      (tester) async {
    final tempDir = Directory('${Directory.systemTemp.path}/history_scan_fab_'
        '${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    final initial = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    addTearDown(() {
      PathProviderPlatform.instance = initial;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final container = ProviderContainer(
      overrides: [
        scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            const AppSettingsState(
              savePath: '',
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

    router.push('/history');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HistoryScreen), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byType(CameraScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(scanStarts, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
