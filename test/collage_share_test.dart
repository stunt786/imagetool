// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';
import 'package:pixeltools/features/collage_builder/notifiers/collage_notifier.dart';
import 'package:pixeltools/features/collage_builder/widgets/collage_toolbar.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/interstitial_tracker.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

class FakeSharePlatform extends Fake
    with MockPlatformInterfaceMixin
    implements SharePlatform {
  List<XFile>? lastSharedFiles;
  String? lastSubject;
  String? lastText;
  Rect? lastOrigin;
  int shareCallCount = 0;

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    shareCallCount++;
    lastSharedFiles = files;
    lastSubject = subject;
    lastText = text;
    lastOrigin = sharePositionOrigin;
    return const ShareResult('success', ShareResultStatus.success);
  }
}

Uint8List _createSolidTestJpg({int width = 200, int height = 200, required Color color}) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgb8(
      (color.r * 255).round().clamp(0, 255),
      (color.g * 255).round().clamp(0, 255),
      (color.b * 255).round().clamp(0, 255),
    ),
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSharePlatform fakeShare;
  late SharePlatform initialSharePlatform;
  late PathProviderPlatform initialPathProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InterstitialTracker.instance.reset();
    fakeShare = FakeSharePlatform();
    initialSharePlatform = SharePlatform.instance;
    SharePlatform.instance = fakeShare;

    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  tearDown(() {
    SharePlatform.instance = initialSharePlatform;
    PathProviderPlatform.instance = initialPathProvider;
  });

  group('Collage Export Logic and Concurrency Hardening', () {
    test('exportCollage prevents concurrent exports', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      final redImg = _createSolidTestJpg(width: 100, height: 100, color: Colors.red);
      notifier.setSlotImage(0, redImg, 'red.jpg');

      // First export starts
      final future1 = notifier.exportCollage();
      // Second concurrent export attempt while isExporting is true
      final future2 = notifier.exportCollage();

      final result2 = await future2;
      expect(result2, isNull, reason: 'Concurrent export must be rejected and return null');

      final result1 = await future1;
      expect(result1, isNotNull);
      expect(result1!.isNotEmpty, isTrue);
    });

    test('exportCollage handles narrow slots and large gaps without negative dimension errors', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      // Max gap with a layout having 3 rows/cols
      notifier.setGap(20.0);
      notifier.setCornerRadius(10.0);
      final layout3x3 = CollageLayout.all.firstWhere((l) => l.id == 'grid_3x3');
      notifier.changeLayout(layout3x3);

      final imgBytes = _createSolidTestJpg(width: 50, height: 50, color: Colors.blue);
      notifier.setSlotImage(0, imgBytes, 'blue.jpg');

      final bytes = await notifier.exportCollage();
      expect(bytes, isNotNull);
      final decoded = img.decodeImage(bytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(1080));
      expect(decoded.height, equals(1080));
    });

    test('exportCollage successfully includes text layers and legacy captionText', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      final imgBytes = _createSolidTestJpg(width: 100, height: 100, color: Colors.green);
      notifier.setSlotImage(0, imgBytes, 'green.jpg');
      notifier.addTextLayer();
      final layerId = container.read(collageProvider).textLayers.first.id;
      notifier.updateTextLayer(layerId, text: 'Layer Text');
      notifier.setCaptionText('Legacy Caption');

      final bytes = await notifier.exportCollage();
      expect(bytes, isNotNull);
      final decoded = img.decodeImage(bytes!);
      expect(decoded, isNotNull);
    });
  });

  group('CollageToolbar Sharing and UI Interaction', () {
    testWidgets('Save and Share buttons are disabled when no images are present', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save to Gallery'),
      );
      expect(saveButton.onPressed, isNull);

      final shareButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Share'),
      );
      expect(shareButton.onPressed, isNull);
    });

    testWidgets('Save and Share buttons are enabled when images exist', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(collageProvider.notifier);
      final testImg = _createSolidTestJpg(width: 100, height: 100, color: Colors.amber);
      notifier.setSlotImage(0, testImg, 'amber.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save to Gallery'),
      );
      expect(saveButton.onPressed, isNotNull);

      final shareButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Share'),
      );
      expect(shareButton.onPressed, isNotNull);
    });

    testWidgets('Tapping Share triggers export, provides valid XFile with MIME type and origin, without hanging', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(collageProvider.notifier);
      final testImg = _createSolidTestJpg(width: 100, height: 100, color: Colors.purple);
      notifier.setSlotImage(0, testImg, 'purple.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageToolbar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shareButtonFinder = find.widgetWithText(FilledButton, 'Share');
      expect(shareButtonFinder, findsOneWidget);

      await tester.tap(shareButtonFinder);
      await tester.pump();
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }

      // Check SharePlatform was called
      expect(fakeShare.shareCallCount, equals(1));
      expect(fakeShare.lastSharedFiles, isNotNull);
      expect(fakeShare.lastSharedFiles!.length, equals(1));

      final sharedXFile = fakeShare.lastSharedFiles!.first;
      expect(sharedXFile.mimeType, equals('image/jpeg'));
      expect(sharedXFile.name, endsWith('.jpg'));

      // Check that text parameter is NOT passed (avoids Android stream/text corruption)
      expect(fakeShare.lastText, isNull);
      expect(fakeShare.lastSubject, isNotNull);

      // Check sharePositionOrigin is non-null for iPad / desktop
      expect(fakeShare.lastOrigin, isNotNull);
      expect(fakeShare.lastOrigin!.width, greaterThan(0));
      expect(fakeShare.lastOrigin!.height, greaterThan(0));

      // Check the shared file exists on disk and is a valid image
      final fileOnDisk = File(sharedXFile.path);
      expect(fileOnDisk.existsSync(), isTrue);
      final bytesOnDisk = fileOnDisk.readAsBytesSync();
      expect(bytesOnDisk.isNotEmpty, isTrue);
      final decodedImage = img.decodeImage(bytesOnDisk);
      expect(decodedImage, isNotNull);
      expect(decodedImage!.width, equals(1080));
      expect(decodedImage.height, equals(1080));

      // Ensure the UI returned to idle state and button says 'Share' again
      expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
    });
  });
}
