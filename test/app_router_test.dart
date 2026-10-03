// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/camera/presentation/camera_screen.dart';
import 'package:pixeltools/features/files/presentation/files_screen.dart';
import 'package:pixeltools/features/files/presentation/history_screen.dart';
import 'package:pixeltools/features/format_converter/presentation/format_converter_screen.dart';
import 'package:pixeltools/features/home/presentation/home_screen.dart';
import 'package:pixeltools/features/image_resize/presentation/image_resize_screen.dart';
import 'package:pixeltools/features/pdf_compress/presentation/pdf_compress_screen.dart';
import 'package:pixeltools/features/pdf_merge/presentation/pdf_merge_screen.dart';
import 'package:pixeltools/features/pdf_split/presentation/pdf_split_screen.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// Builds the real [appRouterProvider] inside a container and pumps it.
Future<_RouterHarness> _pumpRouter(WidgetTester tester) async {
  final container = ProviderContainer();
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
  return _RouterHarness(container, router);
}

class _RouterHarness {
  _RouterHarness(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  /// Current location, or null when the match list is empty (unknown route).
  String? get location {
    try {
      return router.state.uri.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> go(WidgetTester tester, String location) async {
    router.go(location);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initialPathProvider;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('app_router_test_');
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = initialPathProvider;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('the router starts on /tools and shows the home screen',
      (tester) async {
    final harness = await _pumpRouter(tester);

    expect(harness.location, '/tools');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('legacy deep links redirect to their canonical routes',
      (tester) async {
    final harness = await _pumpRouter(tester);

    const aliases = <String, String>{
      '/': '/tools',
      '/home': '/tools',
      '/image-resizer': '/images/resizer',
      '/collage-builder': '/images/collage',
      '/format-converter': '/images/convert',
      '/image-to-pdf': '/images/to-pdf',
      '/pdf-compressor': '/pdfs/compress',
      '/pdf-merger': '/pdfs/merge',
      '/pdf-splitter': '/pdfs/split',
      '/pdf-converter': '/pdfs/convert',
    };

    for (final entry in aliases.entries) {
      await harness.go(tester, entry.key);
      expect(harness.location, entry.value,
          reason: '${entry.key} must redirect to ${entry.value}');
    }
  });

  testWidgets('/onboarding is gated away to the tool list', (tester) async {
    final harness = await _pumpRouter(tester);

    await harness.go(tester, '/onboarding');
    expect(harness.location, '/tools');

    // And it stays gated once settings finish loading.
    await harness.container
        .read(appSettingsProvider.notifier)
        .setCompletedOnboarding(true);
    await tester.pump(const Duration(milliseconds: 200));
    await harness.go(tester, '/onboarding');
    expect(harness.location, '/tools');
  });

  testWidgets('a settings change re-evaluates redirects without moving the '
      'user', (tester) async {
    final harness = await _pumpRouter(tester);
    await harness.go(tester, '/settings');
    expect(harness.location, '/settings');

    await harness.container.read(appSettingsProvider.notifier).setThemeMode(
          ThemeMode.dark,
        );
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.location, '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('key tool routes render their own screens', (tester) async {
    final harness = await _pumpRouter(tester);

    const routes = <String, Type>{
      '/images/resizer': ImageResizeScreen,
      '/images/convert': FormatConverterScreen,
      '/pdfs/compress': PdfCompressScreen,
      '/pdfs/merge': PdfMergeScreen,
      '/pdfs/split': PdfSplitScreen,
      '/history': HistoryScreen,
      '/pdfs': FilesScreen,
      '/camera': CameraScreen,
      '/settings': SettingsScreen,
      '/tools': HomeScreen,
    };

    for (final entry in routes.entries) {
      await harness.go(tester, entry.key);
      expect(harness.location, entry.key);
      expect(find.byType(entry.value), findsOneWidget,
          reason: '${entry.key} should build a ${entry.value}');
    }
  });

  testWidgets('an unknown location shows the router error screen',
      (tester) async {
    final harness = await _pumpRouter(tester);

    await harness.go(tester, '/definitely/not/a/route');

    expect(harness.location, isNull,
        reason: 'an unmatched location has an empty match list');
    expect(find.text('Not found'), findsOneWidget);
    expect(find.textContaining('route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the router is reusable: going back to /tools still works',
      (tester) async {
    final harness = await _pumpRouter(tester);

    await harness.go(tester, '/nope');
    expect(find.text('Not found'), findsOneWidget);

    await harness.go(tester, '/tools');
    expect(harness.location, '/tools');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Not found'), findsNothing);
  });
}
