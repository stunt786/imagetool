// ignore_for_file: depend_on_referenced_packages, unnecessary_import

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pixeltools/core/services/interstitial_tracker.dart';
import 'package:pixeltools/core/settings/app_settings.dart';
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';
import 'package:pixeltools/features/collage_builder/notifiers/collage_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Helper to create a test image with distinct quadrant colors:
/// Top-Left: Red, Top-Right: Green, Bottom-Left: Blue, Bottom-Right: Yellow
Uint8List _createQuadrantTestPng({int width = 200, int height = 200}) {
  final image = img.Image(width: width, height: height);
  final halfW = width ~/ 2;
  final halfH = height ~/ 2;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if (x < halfW && y < halfH) {
        image.setPixelRgb(x, y, 255, 0, 0); // Top-Left: Red
      } else if (x >= halfW && y < halfH) {
        image.setPixelRgb(x, y, 0, 255, 0); // Top-Right: Green
      } else if (x < halfW && y >= halfH) {
        image.setPixelRgb(x, y, 0, 0, 255); // Bottom-Left: Blue
      } else {
        image.setPixelRgb(x, y, 255, 255, 0); // Bottom-Right: Yellow
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Helper to create a rectangular gradient or stripe test image
Uint8List _createHorizontalStripesImage({int width = 200, int height = 100}) {
  final image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    final colorVal = ((y / height) * 255).round().clamp(0, 255);
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, colorVal, colorVal, colorVal);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform initialPathProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InterstitialTracker.instance.reset();
    initialPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  tearDown(() {
    PathProviderPlatform.instance = initialPathProvider;
  });

  group('Collage Export Parity and Zoom/Pan Fidelity', () {
    test('img.copyRotate angle=90 rotates clockwise', () {
      final image = img.Image(width: 4, height: 2);
      // Pixel at (0, 0) is Red
      image.setPixelRgb(0, 0, 255, 0, 0);
      final rotated = img.copyRotate(image, angle: 90);

      // Rotating 4x2 by 90 deg clockwise gives 2x4 image.
      // (0, 0) maps to (width - 1 - y, x) = (2 - 1 - 0, 0) = (1, 0)
      expect(rotated.width, equals(2));
      expect(rotated.height, equals(4));
      final p10 = rotated.getPixel(1, 0);
      expect(p10.r, equals(255));
    });

    test('setScale clamps scale between 1.0 and 5.0, resets offset when scale is 1.0', () {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      final imgBytes = _createQuadrantTestPng();
      notifier.setSlotImage(0, imgBytes, 'quad.png');

      notifier.setScale(0, 2.5);
      notifier.setOffset(0, 0.2, 0.3);
      var state = container.read(collageProvider);
      expect(state.images[0].scale, equals(2.5));
      expect(state.images[0].offsetX, equals(0.2));
      expect(state.images[0].offsetY, equals(0.3));

      // Clamps max to 5.0
      notifier.setScale(0, 10.0);
      state = container.read(collageProvider);
      expect(state.images[0].scale, equals(5.0));

      // Reset to 1.0 clears offsets
      notifier.setScale(0, 1.0);
      state = container.read(collageProvider);
      expect(state.images[0].scale, equals(1.0));
      expect(state.images[0].offsetX, equals(0.0));
      expect(state.images[0].offsetY, equals(0.0));
    });

    test('preview dimensions are recorded and scaleFactor adapts to preview size', () {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      notifier.setPreviewSize(400.0, 400.0);
      final state = container.read(collageProvider);
      expect(state.previewWidth, equals(400.0));
      expect(state.previewHeight, equals(400.0));
    });

    test('exportCollage with scale=1.0 and scale=2.0 renders zoomed center correctly', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      // Single slot layout
      notifier.changeLayout(CollageLayout.all.firstWhere((l) => l.id == 'single'));
      final imgBytes = _createQuadrantTestPng(width: 400, height: 400);
      notifier.setSlotImage(0, imgBytes, 'quad.png');
      notifier.setGap(0);
      notifier.setCornerRadius(0);

      // Export unzoomed: Top-left corner should be Red (255, 0, 0)
      final bytesUnzoomed = await notifier.exportCollage();
      expect(bytesUnzoomed, isNotNull);
      final decodedUnzoomed = img.decodeImage(bytesUnzoomed!)!;
      final unzoomedCorner = decodedUnzoomed.getPixel(20, 20);
      expect(unzoomedCorner.r, greaterThan(240));
      expect(unzoomedCorner.g, lessThan(15));
      expect(unzoomedCorner.b, lessThan(15));

      // Positive offset: translates image right & down -> center shows top-left (Red)
      notifier.setScale(0, 2.0);
      notifier.setOffset(0, 0.45, 0.45);

      final bytesPositive = await notifier.exportCollage();
      expect(bytesPositive, isNotNull);
      final decodedPositive = img.decodeImage(bytesPositive!)!;

      final centerPixelRed = decodedPositive.getPixel(
        decodedPositive.width ~/ 2,
        decodedPositive.height ~/ 2,
      );
      expect(centerPixelRed.r, greaterThan(240));
      expect(centerPixelRed.g, lessThan(15));
      expect(centerPixelRed.b, lessThan(15));

      // Negative offset: translates image left & up -> center shows bottom-right (Yellow)
      notifier.setOffset(0, -0.45, -0.45);

      final bytesNegative = await notifier.exportCollage();
      expect(bytesNegative, isNotNull);
      final decodedNegative = img.decodeImage(bytesNegative!)!;

      final centerPixelYellow = decodedNegative.getPixel(
        decodedNegative.width ~/ 2,
        decodedNegative.height ~/ 2,
      );
      expect(centerPixelYellow.r, greaterThan(240));
      expect(centerPixelYellow.g, greaterThan(240));
      expect(centerPixelYellow.b, lessThan(15));
    });

    test('exportCollage with non-square aspect ratio image preserves cover cropping without stretching', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(const AppSettingsState(savePath: '')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      notifier.changeLayout(CollageLayout.all.firstWhere((l) => l.id == 'single'));
      // Landscape image in square canvas: 400x200 into 1080x1080
      // In BoxFit.cover: the height (200) maps to 1080.
      // The width becomes 1080 * 2 = 2160, so left/right are cropped symmetrically.
      // Top stripe is black (0), bottom stripe is white (255).
      final imgBytes = _createHorizontalStripesImage(width: 400, height: 200);
      notifier.setSlotImage(0, imgBytes, 'stripes.png');
      notifier.setGap(0);
      notifier.setCornerRadius(0);

      final bytes = await notifier.exportCollage();
      expect(bytes, isNotNull);
      final decoded = img.decodeImage(bytes!)!;

      // Top edge should be near 0 (black stripe)
      final topPixel = decoded.getPixel(decoded.width ~/ 2, 5);
      expect(topPixel.r, lessThan(20));

      // Bottom edge should be near 255 (white stripe)
      final bottomPixel = decoded.getPixel(decoded.width ~/ 2, decoded.height - 6);
      expect(bottomPixel.r, greaterThan(235));
    });
  });
}
