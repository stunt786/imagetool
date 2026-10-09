// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/router/app_router.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/home/presentation/home_screen.dart';
import 'package:pixeltools/shared/models/edit_history_item.dart';
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
  setUp(() {
    final seeded = EditHistoryItem.encodeList([
      EditHistoryItem(
        fileName: 'scan_001.jpg',
        toolUsed: 'Scan',
        editedAt: DateTime(2026, 1, 1),
      ),
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'completed_onboarding': true,
      'edit_history_v1': seeded,
    });
  });

  testWidgets('home recent files can be cleared from the section header',
      (tester) async {
    final initial = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider('/tmp');
    addTearDown(() => PathProviderPlatform.instance = initial);

    final container = ProviderContainer(
      overrides: [
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

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Recent Files'), findsOneWidget);
    expect(find.text('Recent History'), findsNothing);
    expect(find.text('scan_001.jpg'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear history?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clear'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear history?'), findsNothing);
    expect(find.text('scan_001.jpg'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Recent Files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
