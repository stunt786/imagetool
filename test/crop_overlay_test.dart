import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/image_resize/models/crop_geometry.dart';
import 'package:pixeltools/features/image_resize/widgets/crop_overlay.dart';

Uint8List _squareImage(int size) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(200, 210, 220));
  img.fillRect(image,
      x1: 0,
      y1: 0,
      x2: size ~/ 2,
      y2: size ~/ 2,
      color: img.ColorRgb8(40, 60, 90));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

void main() {
  // 400x400 surface; an 800x800 image therefore fits at scale 0.5, so screen
  // coordinates are half the image coordinates and local == global.
  const surface = Size(400, 400);
  const imageWidth = 800;
  const imageHeight = 800;

  // Crop (200,200)-(600,600) in image px => screen (100,100)-(300,300).
  const initialCrop =
      CropRect(left: 200, top: 200, right: 600, bottom: 600);

  late Uint8List bytes;

  setUpAll(() {
    bytes = _squareImage(imageWidth);
  });

  /// Bounded pumping: the overlay can show an indeterminate progress badge.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  /// Pumps the overlay and returns the list of committed crop rectangles,
  /// which grows as gestures finish.
  Future<List<CropRect>> pumpOverlay(
    WidgetTester tester, {
    CropRect? crop,
    double? aspectRatio,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final commits = <CropRect>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CropOverlay(
            imageBytes: bytes,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            crop: crop ?? initialCrop,
            aspectRatio: aspectRatio,
            onCropCommitted: commits.add,
          ),
        ),
      ),
    );
    await settle(tester);
    return commits;
  }

  CropViewport viewport(WidgetTester tester) =>
      tester.state<CropOverlayState>(find.byType(CropOverlay)).viewport;

  /// On-screen footprint of the image layer.
  Size imageLayerSize(WidgetTester tester) =>
      tester.getSize(find.byKey(CropOverlayState.imageLayerKey));

  Offset imageLayerOrigin(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(CropOverlayState.imageLayerKey));

  /// Performs a multi-step drag so the gesture recogniser sees a realistic
  /// movement stream (a single jump is consumed by the pan slop).
  Future<void> dragBy(
    WidgetTester tester,
    Offset start,
    Offset total, {
    int steps = 8,
  }) async {
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(total / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
  }

  Future<void> pinch(
    WidgetTester tester, {
    required Offset centre,
    required double spread,
  }) async {
    final first = await tester.startGesture(centre - Offset(spread, 0));
    final second = await tester.startGesture(centre + Offset(spread, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await first.moveBy(const Offset(-12, 0));
      await second.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await settle(tester);
  }

  group('CropOverlay — handles are independent (regression)', () {
    testWidgets('top handle changes only the top edge and never moves the image',
        (tester) async {
      final commits = await pumpOverlay(tester);
      final before = viewport(tester);

      await dragBy(tester, const Offset(200, 100), const Offset(0, -60));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.top, lessThan(initialCrop.top));
      expect(result.left, initialCrop.left);
      expect(result.right, initialCrop.right);
      expect(result.bottom, initialCrop.bottom);

      // The reported bug: the image/workspace must not move.
      expect(viewport(tester).pan, before.pan);
      expect(viewport(tester).scale, before.scale);
    });

    testWidgets('bottom handle changes only the bottom edge', (tester) async {
      final commits = await pumpOverlay(tester);

      await dragBy(tester, const Offset(200, 300), const Offset(0, 60));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.bottom, greaterThan(initialCrop.bottom));
      expect(result.top, initialCrop.top);
      expect(result.left, initialCrop.left);
      expect(result.right, initialCrop.right);
    });

    testWidgets('left handle changes only the left edge', (tester) async {
      final commits = await pumpOverlay(tester);

      await dragBy(tester, const Offset(100, 200), const Offset(60, 0));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.left, greaterThan(initialCrop.left));
      expect(result.top, initialCrop.top);
      expect(result.bottom, initialCrop.bottom);
      expect(result.right, initialCrop.right);
    });

    testWidgets('right handle changes only the right edge', (tester) async {
      final commits = await pumpOverlay(tester);

      await dragBy(tester, const Offset(300, 200), const Offset(-60, 0));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.right, lessThan(initialCrop.right));
      expect(result.top, initialCrop.top);
      expect(result.left, initialCrop.left);
      expect(result.bottom, initialCrop.bottom);
    });

    testWidgets('edge handles ignore the perpendicular axis', (tester) async {
      final commits = await pumpOverlay(tester);

      await dragBy(tester, const Offset(200, 100), const Offset(50, -60));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.left, initialCrop.left);
      expect(result.right, initialCrop.right);
      expect(result.bottom, initialCrop.bottom);
      expect(result.top, lessThan(initialCrop.top));
    });

    testWidgets('dragging inside the rectangle moves it without resizing',
        (tester) async {
      final commits = await pumpOverlay(tester);

      await dragBy(tester, const Offset(200, 200), const Offset(-40, -40));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.width, closeTo(initialCrop.width, 1.5));
      expect(result.height, closeTo(initialCrop.height, 1.5));
      expect(result.left, lessThan(initialCrop.left));
      expect(result.top, lessThan(initialCrop.top));
      expect(result.right, lessThanOrEqualTo(800));
      expect(result.bottom, lessThanOrEqualTo(800));
    });
  });

  group('CropOverlay — image gestures', () {
    testWidgets('a pinch zooms the image and never touches the crop',
        (tester) async {
      final commits = await pumpOverlay(tester);
      final before = viewport(tester);

      await pinch(tester, centre: const Offset(200, 200), spread: 60);

      expect(viewport(tester).scale, greaterThan(before.scale));
      expect(commits, isEmpty);
    });

    testWidgets('a double tap resets the zoom', (tester) async {
      await pumpOverlay(tester);
      final fittedScale = viewport(tester).scale;

      await pinch(tester, centre: const Offset(200, 200), spread: 60);
      expect(viewport(tester).scale, greaterThan(fittedScale));

      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(200, 200));
      await settle(tester);

      expect(viewport(tester).scale, closeTo(fittedScale, 1e-6));
    });

    testWidgets('dragging outside the crop pans a zoomed image only',
        (tester) async {
      // Anchor the crop in a corner so there is empty space left to grab.
      final commits = await pumpOverlay(
        tester,
        crop: const CropRect(left: 0, top: 0, right: 200, bottom: 200),
      );

      // Panning is only meaningful once the image is larger than the viewport.
      await pinch(tester, centre: const Offset(200, 200), spread: 60);
      final before = viewport(tester).pan;

      // Far from the crop rectangle and from any handle.
      await dragBy(tester, const Offset(300, 300), const Offset(0, 50));

      expect(viewport(tester).pan, isNot(before));
      expect(commits, isEmpty);
    });
  });

  group('CropOverlay — aspect ratio', () {
    testWidgets('keeps the locked ratio while dragging a corner',
        (tester) async {
      final commits = await pumpOverlay(tester, aspectRatio: 1);

      await dragBy(tester, const Offset(300, 300), const Offset(50, 10));

      final result = commits.isEmpty ? null : commits.last;
      expect(result, isNotNull);
      expect(result!.width, closeTo(result.height, 2.0));
      expect(result.left, greaterThanOrEqualTo(0));
      expect(result.top, greaterThanOrEqualTo(0));
      expect(result.right, lessThanOrEqualTo(800));
      expect(result.bottom, lessThanOrEqualTo(800));
    });
  });

  group('CropOverlay — the preview fills the frame', () {
    testWidgets('a square image fills a square frame exactly', (tester) async {
      await pumpOverlay(tester);

      // 800x800 image in a 400x400 frame => the image must cover the frame.
      expect(imageLayerSize(tester), const Size(400, 400));
      expect(imageLayerOrigin(tester), Offset.zero);
      expect(viewport(tester).scale, 1.0);
    });

    testWidgets('a landscape image is letterboxed, not shrunk into a corner',
        (tester) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CropOverlay(
              imageBytes: bytes,
              imageWidth: 1600,
              imageHeight: 800,
              crop: initialCrop,
            ),
          ),
        ),
      );
      await settle(tester);

      // fitScale = min(400/1600, 400/800) = 0.25 => 400x200, centred vertically.
      expect(imageLayerSize(tester), const Size(400, 200));
      expect(imageLayerOrigin(tester), const Offset(0, 100));
      expect(viewport(tester).fittedSize, const Size(400, 200));
    });
  });
}
