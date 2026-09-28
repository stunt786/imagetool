import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pixeltools/features/camera/presentation/camera_screen.dart';
import 'package:pixeltools/features/camera/services/scanner_capability_service.dart';
import 'package:pixeltools/features/shell/presentation/app_shell.dart';

class _AlwaysAvailable implements ScannerCapabilityService {
  @override
  Future<bool> isGoogleDocumentScannerAvailable() async => true;
}

void main() {
  const channel = MethodChannel('google_mlkit_document_scanner');
  var scanStarts = 0;

  setUp(() {
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

  /// Lets post-frame callbacks, the capability probe and the scanner's
  /// 200ms teardown delay all run.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the camera tab opens the ML Kit scanner on every visit',
      (tester) async {
    StatefulNavigationShell? shell;
    final router = GoRouter(
      initialLocation: '/x',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            shell = navigationShell;
            return AppShell(navigationShell: navigationShell);
          },
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/x',
                  builder: (context, state) =>
                      const Center(child: Text('home')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/camera',
                  builder: (context, state) => const CameraScreen(),
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
        overrides: <Override>[
          scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    expect(scanStarts, 0);

    // First visit: the ML Kit scanner must open straight away.
    shell!.goBranch(1);
    await settle(tester);
    expect(scanStarts, 1, reason: 'first visit must open the ML Kit scanner');
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Scan a document'), findsNothing);

    // Visiting camera tab again: it must open again.
    shell!.goBranch(1);
    await settle(tester);
    expect(
      scanStarts,
      2,
      reason: 'returning to the camera tab must reopen the ML Kit scanner',
    );
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Scan a document'), findsNothing);

    // And again, to cover repeated back-and-forth.
    shell!.goBranch(1);
    await settle(tester);
    expect(scanStarts, 3);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Scan a document'), findsNothing);

    // Tapping the camera tab while already on camera reopens ML Kit scanner
    final cameraNavFinder = find.widgetWithText(InkWell, 'Camera');
    if (cameraNavFinder.evaluate().isNotEmpty) {
      await tester.tap(cameraNavFinder);
      await settle(tester);
      expect(scanStarts, 4, reason: 'tapping camera tab again must reopen ML Kit scanner');
      expect(find.text('Scan a document'), findsNothing);
    }
  });

  testWidgets('cameraLaunchTriggerProvider opens ML Kit scanner when active',
      (tester) async {
    late ProviderContainer container;
    final router = GoRouter(
      initialLocation: '/camera',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AppShell(navigationShell: navigationShell);
          },
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/x',
                  builder: (context, state) =>
                      const Center(child: Text('home')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/camera',
                  builder: (context, state) => const CameraScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    container = ProviderContainer(
      overrides: <Override>[
        scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    expect(scanStarts, 1);

    // Trigger manual launch (e.g. from Home Scan Docs button)
    container.read(cameraLaunchTriggerProvider.notifier).state++;
    await settle(tester);
    expect(scanStarts, 2);
    expect(find.text('Scan a document'), findsNothing);
  });

  testWidgets('camera screen handles back navigation via PopScope',
      (tester) async {
    StatefulNavigationShell? shell;
    final router = GoRouter(
      initialLocation: '/x',
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            shell = navigationShell;
            return AppShell(navigationShell: navigationShell);
          },
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/x',
                  builder: (context, state) =>
                      const Center(child: Text('home screen')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/camera',
                  builder: (context, state) => const CameraScreen(),
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
        overrides: <Override>[
          scannerCapabilityProvider.overrideWithValue(_AlwaysAvailable()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    expect(find.text('home screen'), findsOneWidget);

    shell!.goBranch(1);
    await settle(tester);
    // After scan is cancelled, should return to home screen, never trapped on fallback
    expect(find.text('home screen'), findsOneWidget);
    expect(find.text('Google document scanner'), findsNothing);
  });
}
