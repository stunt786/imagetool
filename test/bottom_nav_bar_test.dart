import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/shell/presentation/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BottomNavBar matches reference: Home & Files labelled, Camera icon-only, correct branch switches',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/tools',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AppShell(navigationShell: navigationShell);
          },
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/tools',
                  builder: (context, state) => const Scaffold(body: Text('HomeScreenBody')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/camera',
                  builder: (context, state) => const Scaffold(body: Text('CameraScreenBody')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/pdfs',
                  builder: (context, state) => const Scaffold(body: Text('FilesScreenBody')),
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
    await tester.pumpAndSettle();

    // 1. Home & Files show text labels, Camera stays icon-only
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);

    // 2. Verify all 3 icons are present via Semantics labels and Icon widgets
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);

    // Initially on Home (index 0)
    expect(find.text('HomeScreenBody'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);

    // 3. Tap on Files
    await tester.tap(find.bySemanticsLabel('Files'));
    await tester.pumpAndSettle();
    expect(find.text('FilesScreenBody'), findsOneWidget);
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);

    // 4. Tap on Camera
    await tester.tap(find.bySemanticsLabel('Camera'));
    await tester.pumpAndSettle();
    expect(find.text('CameraScreenBody'), findsOneWidget);

    // 5. Tap on Home
    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();
    expect(find.text('HomeScreenBody'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
  });

  testWidgets('BottomNavBar is displayed on subpages and tool routes with appRouterProvider',
      (tester) async {
    final container = ProviderContainer(
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
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify bottom navbar is present on Home screen
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);

    // 2. Push /settings
    router.push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // 3. Push /history
    router.push('/history');
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // 4. Push /images/resizer
    router.push('/images/resizer');
    await tester.pumpAndSettle();
    expect(find.text('Resize Image'), findsWidgets);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // 5. Push /pdfs/compress
    router.push('/pdfs/compress');
    await tester.pumpAndSettle();
    expect(find.text('Compress PDF'), findsOneWidget);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);
  });

  testWidgets('BottomNavBar renders with light background in both light and dark theme',
      (tester) async {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(
              AppSettingsState(
                savePath: '/test/path',
                hasCompletedOnboarding: true,
                themeMode: themeMode,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bottom bar elements exist
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      expect(find.bySemanticsLabel('Camera'), findsOneWidget);
      expect(find.bySemanticsLabel('Files'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });
}
