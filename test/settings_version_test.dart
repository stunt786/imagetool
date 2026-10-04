import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixeltools/core/services/app_info_service.dart';
import 'package:pixeltools/core/services/app_update_service.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppInfoService dynamic version', () {
    test('reads dynamic version from platform package info', () async {
      PackageInfo.setMockInitialValues(
        appName: 'PixelTools',
        packageName: 'com.bnbkio.pixeltools',
        version: '1.0.1',
        buildNumber: '2',
        buildSignature: '',
      );

      final appInfo = await AppInfoService.instance.getAppInfo();
      expect(appInfo.version, '1.0.1');
      expect(appInfo.buildNumber, '2');
      expect(appInfo.versionWithBuild, '1.0.1+2');
      expect(AppUpdateService.currentAppVersion, '1.0.1');
      expect(AppUpdateService.currentBuildNumber, '2');
    });

    test('updates when version in package info changes', () async {
      PackageInfo.setMockInitialValues(
        appName: 'PixelTools',
        packageName: 'com.bnbkio.pixeltools',
        version: '2.0.0',
        buildNumber: '15',
        buildSignature: '',
      );

      // Force refresh info
      final info = await PackageInfo.fromPlatform();
      expect(info.version, '2.0.0');
      expect(info.buildNumber, '15');
    });
  });

  group('SettingsScreen dynamic version display', () {
    testWidgets('displays dynamic version in SettingsScreen', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'PixelTools',
        packageName: 'com.bnbkio.pixeltools',
        version: '1.0.1',
        buildNumber: '2',
        buildSignature: '',
      );

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsNotifier(
                const AppSettingsState(
                  savePath: '/test/save/path',
                  hasCompletedOnboarding: true,
                ),
              ),
            ),
            appInfoProvider.overrideWith(
              (ref) async => const AppInfo(
                appName: 'PixelTools',
                packageName: 'com.bnbkio.pixeltools',
                version: '1.0.1',
                buildNumber: '2',
              ),
            ),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.drag(find.text('Share the App'), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Version'), findsOneWidget);
      expect(find.text('1.0.1'), findsOneWidget);
    });

    testWidgets('reflects bumped version in SettingsScreen when pubspec version changes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              (ref) => AppSettingsNotifier(
                const AppSettingsState(
                  savePath: '/test/save/path',
                  hasCompletedOnboarding: true,
                ),
              ),
            ),
            appInfoProvider.overrideWith(
              (ref) async => const AppInfo(
                appName: 'PixelTools',
                packageName: 'com.bnbkio.pixeltools',
                version: '1.2.0',
                buildNumber: '5',
              ),
            ),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.drag(find.text('Share the App'), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Version'), findsOneWidget);
      expect(find.text('1.2.0'), findsOneWidget);
    });
  });
}
