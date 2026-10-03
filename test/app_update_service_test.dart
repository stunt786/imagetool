import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixeltools/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUpdateService.instance.customUpdateChecker = null;
    AppUpdateService.instance.remoteManifestUrl = null;
  });

  group('AppUpdateService version parsing & comparison', () {
    test('isNewerVersion detects major, minor, and patch upgrades', () {
      expect(AppUpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(AppUpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(AppUpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(AppUpdateService.isNewerVersion('1.0.0+2', '1.0.0+1'), isFalse); // build numbers ignored in clean semver
      expect(AppUpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(AppUpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });
  });

  group('AppUpdateService 2-day deferral rule', () {
    test('shouldCheckAutoUpdate is true initially when no postponement recorded', () async {
      final prefs = await SharedPreferences.getInstance();
      final shouldCheck = await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs);
      expect(shouldCheck, isTrue);
    });

    test('postponeUpdate sets postponement timestamp', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppUpdateService.instance.postponeUpdate(testPrefs: prefs);

      final val = prefs.getInt(AppUpdateService.keyPostponedTime);
      expect(val, isNotNull);
      expect(val! > 0, isTrue);

      final shouldCheck = await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs);
      expect(shouldCheck, isFalse);
    });

    test('shouldCheckAutoUpdate returns true after 2 days elapsed', () async {
      final prefs = await SharedPreferences.getInstance();
      // Set timestamp to 49 hours ago (more than 2 days)
      final twoDaysAgoMs = DateTime.now().subtract(const Duration(hours: 49)).millisecondsSinceEpoch;
      await prefs.setInt(AppUpdateService.keyPostponedTime, twoDaysAgoMs);

      final shouldCheck = await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs);
      expect(shouldCheck, isTrue);
    });

    test('shouldCheckAutoUpdate returns false when within 2 days (e.g. 1 day ago)', () async {
      final prefs = await SharedPreferences.getInstance();
      final oneDayAgoMs = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
      await prefs.setInt(AppUpdateService.keyPostponedTime, oneDayAgoMs);

      final shouldCheck = await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs);
      expect(shouldCheck, isFalse);
    });

    test('clearPostponedUpdate removes postponement', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppUpdateService.instance.postponeUpdate(testPrefs: prefs);
      expect(await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs), isFalse);

      await AppUpdateService.instance.clearPostponedUpdate(testPrefs: prefs);
      expect(await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs), isTrue);
    });
  });

  group('AppUpdateService checkForUpdate with custom checker', () {
    test('returns update info from custom checker', () async {
      AppUpdateService.instance.customUpdateChecker = () async {
        return const AppUpdateInfo(
          hasUpdate: true,
          currentVersion: '1.0.0',
          latestVersion: '1.2.0',
          downloadUrl: 'https://example.com/app.apk',
          releaseNotes: ['Note 1', 'Note 2'],
        );
      };

      final info = await AppUpdateService.instance.checkForUpdate();
      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '1.2.0');
      expect(info.releaseNotes.length, 2);
    });
  });
}
