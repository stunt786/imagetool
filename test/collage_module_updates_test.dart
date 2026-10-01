import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';
import 'package:pixeltools/features/collage_builder/notifiers/collage_notifier.dart';
import 'package:pixeltools/features/collage_builder/widgets/collage_canvas.dart';
import 'package:pixeltools/features/collage_builder/widgets/collage_text_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Collage 3x3 Grid Layout Support', () {
    test('CollageLayout.getLayoutForImageCount selects grid_3x3 for 7, 8, and 9 images', () {
      expect(CollageLayout.getLayoutForImageCount(7).id, 'grid_3x3');
      expect(CollageLayout.getLayoutForImageCount(8).id, 'grid_3x3');
      expect(CollageLayout.getLayoutForImageCount(9).id, 'grid_3x3');
      expect(CollageLayout.getLayoutForImageCount(9).slotCount, 9);
    });

    test('maxCollageImages constant is 9', () {
      expect(CollageNotifier.maxCollageImages, 9);
    });

    test('changeLayout preserves and restores cached slots across layout transitions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      final layout3x3 = CollageLayout.all.firstWhere((l) => l.id == 'grid_3x3');
      notifier.changeLayout(layout3x3);
      expect(container.read(collageProvider).layout.slotCount, 9);
      expect(container.read(collageProvider).images.length, 9);

      // Populate slots with test images
      final imgBytes1 = _createSolidTestJpg(color: Colors.red);
      final imgBytes2 = _createSolidTestJpg(color: Colors.blue);

      notifier.setSlotImage(0, imgBytes1, 'img1.jpg');
      notifier.setSlotImage(1, imgBytes2, 'img2.jpg');
      notifier.changeLayout(CollageLayout.all[0]); // Switch to single (1 slot)

      expect(container.read(collageProvider).layout.slotCount, 1);

      // Switch back to 3x3 grid
      notifier.changeLayout(layout3x3);
      final restoredState = container.read(collageProvider);
      expect(restoredState.layout.slotCount, 9);
      // Both images should be preserved
      expect(restoredState.images[0].hasImage, isTrue);
      expect(restoredState.images[1].hasImage, isTrue);
    });
  });

  group('Collage Export Gap and Radius Customization', () {
    test('exportCollage blends rounded corners into backgroundColor without black corners', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith((ref) => AppSettingsNotifier(const AppSettingsState(savePath: ''))),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      const bgColor = Color(0xFFE8EAF6); // Soft lavender background
      notifier.setBackgroundColor(bgColor);
      notifier.setGap(8.0);
      notifier.setCornerRadius(24.0);

      // Provide a test image in slot 0
      final redImg = _createSolidTestJpg(width: 300, height: 300, color: Colors.red);
      final layout1 = CollageLayout.all.firstWhere((l) => l.id == 'single');
      notifier.changeLayout(layout1);
      notifier.setSlotImage(0, redImg, 'red.jpg');

      final exportBytes = await notifier.exportCollage();
      expect(exportBytes, isNotNull);
      expect(exportBytes!.isNotEmpty, isTrue);

      final decoded = img.decodeImage(exportBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(1080));
      expect(decoded.height, equals(1080));

      // Check pixel at (0, 0) top left of canvas - should be background color (allowing JPEG lossy tolerance)
      final cornerPixel = decoded.getPixel(0, 0);
      expect(cornerPixel.r, closeTo((bgColor.r * 255).round(), 3));
      expect(cornerPixel.g, closeTo((bgColor.g * 255).round(), 3));
      expect(cornerPixel.b, closeTo((bgColor.b * 255).round(), 3));
    });
  });

  group('Collage Text Popup Window Widget Tests', () {
    testWidgets('CollageTextDialog renders controls and allows editing text', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(collageProvider.notifier);
      notifier.addTextLayer();
      final layerId = container.read(collageProvider).textLayers.first.id;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: CollageTextDialog(initialLayerId: layerId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Text'), findsOneWidget);
      expect(find.text('Font Family'), findsOneWidget);
      expect(find.text('Text Color'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Enter text
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'New Summer Collage');
      await tester.pumpAndSettle();

      final updatedLayer = container.read(collageProvider).textLayers.first;
      expect(updatedLayer.text, equals('New Summer Collage'));

      // Check font styles are visible
      expect(find.text('Serif'), findsOneWidget);
      expect(find.text('Impact'), findsOneWidget);

      // Tap Serif
      await tester.tap(find.text('Serif'));
      await tester.pumpAndSettle();
      expect(container.read(collageProvider).textLayers.first.fontFamily, equals('serif'));
    });

    testWidgets('CollageCanvas exposes edit handle and onDoubleTap to open text dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(collageProvider.notifier);
      notifier.addTextLayer();
      notifier.updateTextLayer(
        container.read(collageProvider).textLayers.first.id,
        text: 'Canvas Test Text',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageCanvas(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Canvas Test Text'), findsOneWidget);

      // Tap on text to activate (advance past double-tap gesture timeout)
      await tester.tap(find.text('Canvas Test Text'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Edit handle (Icons.edit_rounded) should now be visible on active overlay
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

      // Tap edit handle
      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();

      // Dialog should open
      expect(find.text('Manage Text'), findsOneWidget);
    });

    testWidgets('Slot options bottom sheet stays open across actions until closed', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(collageProvider.notifier);
      final testJpg = _createSolidTestJpg(color: Colors.blue);
      notifier.setSlotImage(0, testJpg, 'test.jpg');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageCanvas(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap slot 0 to open slot options
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Verify sheet is open
      expect(find.text('Slot 1 Options'), findsOneWidget);
      expect(find.text('Zoom In'), findsOneWidget);
      expect(find.text('Zoom Out'), findsOneWidget);
      expect(find.text('Fit Mode'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);

      // Verify SafeArea is used to prevent hiding behind screen bottom
      expect(find.byType(SafeArea), findsWidgets);

      // Tap Zoom In -> should update scale and NOT close the sheet
      final initialScale = container.read(collageProvider).images[0].scale;
      await tester.tap(find.text('Zoom In'));
      await tester.pumpAndSettle();

      expect(container.read(collageProvider).images[0].scale, greaterThan(initialScale));
      expect(find.text('Slot 1 Options'), findsOneWidget); // Sheet is STILL open!

      // Tap Rotate -> should rotate and NOT close the sheet
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();

      expect(container.read(collageProvider).images[0].rotation, 90.0);
      expect(find.text('Slot 1 Options'), findsOneWidget); // Sheet is STILL open!

      // Tap Fit Mode -> should cycle fit mode and NOT close the sheet
      await tester.tap(find.text('Fit Mode'));
      await tester.pumpAndSettle();

      expect(container.read(collageProvider).images[0].fitMode, ImageFitMode.contain);
      expect(find.text('Slot 1 Options'), findsOneWidget); // Sheet is STILL open!

      // Tap close button -> should close sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Slot 1 Options'), findsNothing); // Sheet is now closed!
    });
  });
}

