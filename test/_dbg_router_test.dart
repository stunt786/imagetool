// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/features/format_converter/presentation/format_converter_screen.dart';
import 'package:pixeltools/features/home/presentation/home_screen.dart';
import 'package:pixeltools/features/image_resize/presentation/image_resize_screen.dart';
import 'package:pixeltools/features/pdf_compress/presentation/pdf_compress_screen.dart';
import 'package:pixeltools/features/pdf_merge/presentation/pdf_merge_screen.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'has_completed_onboarding': true,
    });
    PathProviderPlatform.instance =
        _FakePathProvider((await Directory.systemTemp.createTemp('dbg_')).path);
  });

  testWidgets('debug sequences', (tester) async {
    final container = ProviderContainer();
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    String? where() {
      try {
        return router.state.uri.path;
      } catch (_) {
        return null;
      }
    }

    Future<void> go(String loc) async {
      router.go(loc);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
    }

    String summary() =>
        'home=${find.byType(HomeScreen).evaluate().length} '
        'resize=${find.byType(ImageResizeScreen).evaluate().length} '
        'convert=${find.byType(FormatConverterScreen).evaluate().length} '
        'compress=${find.byType(PdfCompressScreen).evaluate().length} '
        'merge=${find.byType(PdfMergeScreen).evaluate().length} '
        'settings=${find.byType(SettingsScreen).evaluate().length}';

    await go('/images/resizer');
    debugPrint('1 resizer: ${where()} ${summary()}');
    await go('/images/convert');
    debugPrint('2 convert: ${where()} ${summary()}');
    await go('/tools');
    debugPrint('3 tools: ${where()} ${summary()}');
    await go('/images/convert');
    debugPrint('4 convert: ${where()} ${summary()}');
    await go('/pdfs/compress');
    debugPrint('5 compress: ${where()} ${summary()}');
    await go('/pdfs/merge');
    debugPrint('6 merge: ${where()} ${summary()}');
    await go('/settings');
    debugPrint('7 settings: ${where()} ${summary()}');
    await go('/tools');
    debugPrint('8 tools: ${where()} ${summary()}');
    await go('/pdfs');
    debugPrint('9 files: ${where()} ${summary()}');
    await go('/tools');
    debugPrint('10 tools: ${where()} ${summary()}');
    await go('/settings');
    debugPrint('11 settings: ${where()} ${summary()}');
    await go('/tools');
    debugPrint('12 tools: ${where()} ${summary()}');
    expect(tester.takeException(), isNull);
  });
}
