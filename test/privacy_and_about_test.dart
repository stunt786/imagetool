import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixeltools/core/constants/app_strings.dart';
import 'package:pixeltools/core/services/app_update_service.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/settings/presentation/about_screen.dart';
import 'package:pixeltools/features/settings/presentation/privacy_policy_screen.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PrivacyPolicyScreen widget tests', () {
    testWidgets('renders privacy policy screen with all sections', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivacyPolicyScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('100% Offline & Privacy-First'), findsOneWidget);
      expect(find.textContaining('On-Device Local Processing'), findsOneWidget);
      expect(find.textContaining('On-Device Machine Learning'), findsOneWidget);
      expect(find.textContaining('Device Permissions & Usage'), findsOneWidget);
      expect(find.textContaining('No Analytics or Tracking'), findsOneWidget);
      expect(find.textContaining('bnbKio'), findsWidgets);
    });
  });

  group('AboutScreen widget tests', () {
    testWidgets('renders app information and developer information section', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text('Image & PDF Editor • Version 1.0.0'), findsOneWidget);
      expect(find.text('Developer Information'), findsOneWidget);

      // Verify the exact text from fix.md
      expect(find.text(AboutScreen.developerAboutUsText), findsOneWidget);

      // Verify main areas chips
      expect(find.text('Mobile App Development'), findsOneWidget);
      expect(find.text('Web Development'), findsOneWidget);
      expect(find.text('Cloud Services'), findsOneWidget);
      expect(find.text('UI/UX Design'), findsOneWidget);
      expect(find.text('AI & Machine Learning'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.text('Share App'), findsOneWidget);
    });
  });

  group('SettingsScreen update & about tiles', () {
    testWidgets('displays Check for Updates, Privacy Policy, and About tiles', (tester) async {
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
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.drag(find.text('Share the App'), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('App & Updates'), findsOneWidget);
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('About & Developer Info'), findsOneWidget);
    });
  });

  group('AppUpdateService dialog tests', () {
    testWidgets('showUpdateDialog displays Update Now & Update Later and Update Later postpones',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    AppUpdateService.instance.showUpdateDialog(
                      context,
                      const AppUpdateInfo(
                        hasUpdate: true,
                        currentVersion: '1.0.0',
                        latestVersion: '1.2.0',
                        downloadUrl: 'https://play.google.com/store',
                        releaseNotes: ['Improved PDF rendering', 'Fixed SnackBar auto-close'],
                      ),
                    );
                  },
                  child: const Text('Open Update Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap button to open dialog
      await tester.tap(find.text('Open Update Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Version 1.2.0'), findsOneWidget);
      expect(find.text("What's New:"), findsOneWidget);
      expect(find.text('Improved PDF rendering'), findsOneWidget);
      expect(find.text('Fixed SnackBar auto-close'), findsOneWidget);
      expect(find.text('Update Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Tap Update Later
      await tester.tap(find.text('Update Later'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('Update Available'), findsNothing);

      // Postponed timestamp set
      final postponedMs = prefs.getInt(AppUpdateService.keyPostponedTime);
      expect(postponedMs, isNotNull);
      expect(postponedMs! > 0, isTrue);

      // Subsequent auto check returns false
      expect(await AppUpdateService.instance.shouldCheckAutoUpdate(testPrefs: prefs), isFalse);
    });
  });
}
