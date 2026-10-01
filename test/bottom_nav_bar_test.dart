import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/shell/presentation/app_shell.dart';

void main() {
  testWidgets('BottomNavBar matches reference: icon-only, no text, correct branch switches',
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

    // 1. Verify NO text in bottom navbar (only in screen body)
    expect(find.text('Home'), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(find.text('Camera'), findsNothing);

    // 2. Verify all 3 icons are present via Semantics labels and Icon widgets
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera'), findsOneWidget);
    expect(find.bySemanticsLabel('Files'), findsOneWidget);

    // Initially on Home (index 0)
    expect(find.text('HomeScreenBody'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.snippet_folder_outlined), findsOneWidget);

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
}
