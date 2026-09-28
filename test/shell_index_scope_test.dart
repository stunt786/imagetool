import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pixeltools/features/shell/presentation/app_shell.dart';
import 'package:pixeltools/features/shell/presentation/shell_index_scope.dart';

final List<_ProbeState> _states = <_ProbeState>[];

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int changes = 0;
  int? lastIndex;

  @override
  void initState() {
    super.initState();
    _states.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    changes++;
    lastIndex = ShellIndexScope.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(_states.clear);

  testWidgets('an already-mounted branch screen is told about every tab '
      'switch, in both directions', (tester) async {
    StatefulNavigationShell? shell;
    final router = GoRouter(
      initialLocation: '/tools',
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
                  path: '/tools',
                  builder: (context, state) => const _Probe(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: '/camera',
                  builder: (context, state) => const _Probe(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Visit the camera branch once so its screen is mounted and stays mounted.
    shell!.goBranch(1);
    await tester.pumpAndSettle();
    expect(_states, hasLength(2), reason: 'home + camera screens exist');
    final camera = _states[1];
    expect(camera.lastIndex, 1);

    final afterFirstVisit = camera.changes;

    // Leave the camera branch.
    shell!.goBranch(0);
    await tester.pumpAndSettle();

    expect(
      camera.changes,
      greaterThan(afterFirstVisit),
      reason: 'the camera screen must be notified when the user leaves it',
    );
    expect(camera.lastIndex, 0);

    final afterLeaving = camera.changes;

    // Come back to the camera branch.
    shell!.goBranch(1);
    await tester.pumpAndSettle();

    expect(
      camera.changes,
      greaterThan(afterLeaving),
      reason: 'the camera screen must be notified when the user returns',
    );
    expect(camera.lastIndex, 1);
  });
}
