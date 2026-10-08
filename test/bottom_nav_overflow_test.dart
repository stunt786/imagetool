import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/shell/presentation/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  const sizes = <String, Size>{
    '320x568': Size(320, 568),
    '360x640': Size(360, 640),
    '412x915': Size(412, 915),
    '640x360': Size(640, 360),
    '812x375': Size(812, 375),
  };
  const scales = <double>[1.0, 1.1, 1.15, 1.3, 1.5, 2.0];

  for (final entry in sizes.entries) {
    for (final scale in scales) {
      testWidgets('nav bar ${entry.key} @ textScale $scale', (tester) async {
        final overflows = <String>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.exception?.toString() ?? details.toString();
          if (text.toLowerCase().contains('overflow')) {
            overflows.add(text);
            return;
          }
          previousOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = previousOnError);

        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        final router = GoRouter(
          initialLocation: '/tools',
          routes: <RouteBase>[
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) =>
                  AppShell(navigationShell: navigationShell),
              branches: <StatefulShellBranch>[
                StatefulShellBranch(
                  routes: <RouteBase>[
                    GoRoute(
                      path: '/tools',
                      builder: (context, state) =>
                          const Scaffold(body: Text('HomeScreenBody')),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: <RouteBase>[
                    GoRoute(
                      path: '/camera',
                      builder: (context, state) =>
                          const Scaffold(body: Text('CameraScreenBody')),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: <RouteBase>[
                    GoRoute(
                      path: '/pdfs',
                      builder: (context, state) =>
                          const Scaffold(body: Text('FilesScreenBody')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appSettingsProvider.overrideWith(
                (ref) => AppSettingsNotifier(
                  const AppSettingsState(
                    savePath: '/test/path',
                    hasCompletedOnboarding: true,
                  ),
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          overflows,
          isEmpty,
          reason: 'Overflow at ${entry.key} @ $scale:\n${overflows.join('\n')}',
        );
      });
    }
  }
}
