import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initial;
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    initial = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider();
  });
  tearDown(() {
    PathProviderPlatform.instance = initial;
  });

  testWidgets('probe router', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('LOC: ${router.state.uri}');
    debugPrint('ex0: ${tester.takeException()}');

    Future<void> go(String loc) async {
      router.go(loc);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
      final loc2 = () {
        try {
          return router.state.uri.toString();
        } catch (e) {
          return 'ERR $e';
        }
      }();
      debugPrint('$loc -> $loc2 | exc=${tester.takeException()}');
    }

    await go('/');
    await go('/home');
    await go('/image-resizer');
    await go('/collage-builder');
    await go('/format-converter');
    await go('/pdf-compressor');
    await go('/pdf-merger');
    await go('/pdf-splitter');
    await go('/pdf-converter');
    await go('/image-to-pdf');
    await go('/onboarding');
    await go('/settings');
    await go('/history');
    await go('/pdfs');
    await go('/camera');
    await go('/images/to-pdf');
    await go('/nope/unknown');
    debugPrint('notfound=${find.text('Not found').evaluate().length}');
    debugPrint('err text=${find.textContaining('no route').evaluate().length}');
  });
}
