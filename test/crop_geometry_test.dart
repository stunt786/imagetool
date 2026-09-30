import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/features/image_resize/models/crop_geometry.dart';

void main() {
  const imageWidth = 1000;
  const imageHeight = 800;
  final viewport = const CropViewport(
    imageSize: Size(1000, 800),
    viewportSize: Size(500, 400),
  );

  group('CropRect', () {
    test('full covers the whole image', () {
      final rect = CropRect.full(imageWidth, imageHeight);
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.width, 1000);
      expect(rect.height, 800);
    });

    test('toPixelRect clamps into the image', () {
      const rect = CropRect(left: -50, top: -20, right: 5000, bottom: 5000);
      final pixels = rect.toPixelRect(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(pixels.x, 0);
      expect(pixels.y, 0);
      expect(pixels.width, lessThanOrEqualTo(imageWidth));
      expect(pixels.height, lessThanOrEqualTo(imageHeight));
      expect(pixels.x + pixels.width, lessThanOrEqualTo(imageWidth));
      expect(pixels.y + pixels.height, lessThanOrEqualTo(imageHeight));
    });

    test('toPixelRect never returns a zero-sized crop', () {
      const rect = CropRect(left: 10, top: 10, right: 10.2, bottom: 10.2);
      final pixels = rect.toPixelRect(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(pixels.width, greaterThanOrEqualTo(1));
      expect(pixels.height, greaterThanOrEqualTo(1));
    });
  });

  group('CropViewport coordinate conversion', () {
    test('fits the image and round-trips image <-> screen points', () {
      expect(viewport.fitScale, closeTo(0.5, 1e-9));
      const imagePoint = Offset(250, 160);
      final screen = viewport.toScreen(imagePoint);
      final back = viewport.toImage(screen);
      expect(back.dx, closeTo(imagePoint.dx, 1e-6));
      expect(back.dy, closeTo(imagePoint.dy, 1e-6));
    });

    test('screen deltas convert to image deltas at the current zoom', () {
      expect(
        viewport.screenDeltaToImage(const Offset(10, -20)),
        const Offset(20, -40),
      );
      final zoomed = viewport.copyWith(scale: 2);
      expect(zoomed.effectiveScale, closeTo(1.0, 1e-9));
      expect(
        zoomed.screenDeltaToImage(const Offset(10, -20)),
        const Offset(10, -20),
      );
    });

    test('zoomAround keeps the focal point stationary', () {
      const focal = Offset(180, 120);
      final before = viewport.toImage(focal);
      final zoomed = viewport.zoomAround(focal, 2.5);
      final after = zoomed.toImage(focal);
      expect(after.dx, closeTo(before.dx, 1e-6));
      expect(after.dy, closeTo(before.dy, 1e-6));
      expect(zoomed.scale, 2.5);
    });

    test('clamping resets pan when not zoomed', () {
      final panned = viewport.copyWith(pan: const Offset(300, 300)).clamped();
      expect(panned.pan, Offset.zero);
      expect(panned.scale, 1.0);
    });
  });

  group('CropGeometry.hitTest', () {
    final crop = CropRect.full(imageWidth, imageHeight).copyWith(
      left: 100,
      top: 100,
      right: 900,
      bottom: 700,
    );

    test('finds every handle', () {
      CropHandle? at(Offset image) => CropGeometry.hitTest(
            screenPosition: viewport.toScreen(image),
            crop: crop,
            viewport: viewport,
          );

      expect(at(const Offset(100, 100)), CropHandle.topLeft);
      expect(at(const Offset(900, 100)), CropHandle.topRight);
      expect(at(const Offset(100, 700)), CropHandle.bottomLeft);
      expect(at(const Offset(900, 700)), CropHandle.bottomRight);
      expect(at(const Offset(500, 100)), CropHandle.top);
      expect(at(const Offset(500, 700)), CropHandle.bottom);
      expect(at(const Offset(100, 400)), CropHandle.left);
      expect(at(const Offset(900, 400)), CropHandle.right);
    });

    test('returns move inside the rectangle and null outside', () {
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(500, 400)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.move,
      );
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(20, 20)),
          crop: crop,
          viewport: viewport,
        ),
        isNull,
      );
    });
  });

  group('CropGeometry.applyDrag regression: handles are independent', () {
    final start = const CropRect(left: 100, top: 100, right: 900, bottom: 700);

    CropRect drag(CropHandle handle, Offset screenDelta) =>
        CropGeometry.applyDrag(
          start: start,
          handle: handle,
          screenDelta: screenDelta,
          viewport: viewport,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );

    test('dragging the TOP handle changes only the top edge', () {
      final result = drag(CropHandle.top, const Offset(0, -40));
      expect(result.top, closeTo(20, 1e-6));
      expect(result.left, start.left);
      expect(result.right, start.right);
      expect(result.bottom, start.bottom);
    });

    test('dragging the BOTTOM handle changes only the bottom edge', () {
      final result = drag(CropHandle.bottom, const Offset(0, 30));
      expect(result.bottom, closeTo(760, 1e-6));
      expect(result.top, start.top);
      expect(result.left, start.left);
      expect(result.right, start.right);
    });

    test('dragging the LEFT handle changes only the left edge', () {
      final result = drag(CropHandle.left, const Offset(20, 0));
      expect(result.left, closeTo(140, 1e-6));
      expect(result.top, start.top);
      expect(result.bottom, start.bottom);
      expect(result.right, start.right);
    });

    test('dragging the RIGHT handle changes only the right edge', () {
      final result = drag(CropHandle.right, const Offset(-20, 0));
      expect(result.right, closeTo(860, 1e-6));
      expect(result.top, start.top);
      expect(result.bottom, start.bottom);
      expect(result.left, start.left);
    });

    test('edge handles ignore the perpendicular axis', () {
      final top = drag(CropHandle.top, const Offset(60, -40));
      expect(top.left, start.left);
      expect(top.right, start.right);
      final left = drag(CropHandle.left, const Offset(20, 60));
      expect(left.top, start.top);
      expect(left.bottom, start.bottom);
    });

    test('move keeps the size and stays inside the image', () {
      final result = drag(CropHandle.move, const Offset(500, 500));
      expect(result.width, start.width);
      expect(result.height, start.height);
      expect(result.left, greaterThanOrEqualTo(0));
      expect(result.top, greaterThanOrEqualTo(0));
      expect(result.right, lessThanOrEqualTo(imageWidth.toDouble()));
      expect(result.bottom, lessThanOrEqualTo(imageHeight.toDouble()));
    });

    test('a handle drag tracks the finger exactly at any zoom', () {
      final zoomed = viewport.copyWith(scale: 2);
      final result = CropGeometry.applyDrag(
        start: start,
        handle: CropHandle.top,
        screenDelta: const Offset(0, -50),
        viewport: zoomed,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      // 50 screen px at effectiveScale 1.0 => 50 image px.
      expect(result.top, closeTo(50, 1e-6));
      // And the handle lands under the finger on screen.
      final movedHandle = zoomed.toScreen(Offset(result.left, result.top)).dy;
      final originalHandle = zoomed.toScreen(start.topLeft).dy;
      expect(originalHandle - movedHandle, closeTo(50, 1e-6));
    });

    test('cannot be dragged outside the image', () {
      final result = drag(CropHandle.move, const Offset(-5000, -5000));
      expect(result.left, greaterThanOrEqualTo(0));
      expect(result.top, greaterThanOrEqualTo(0));
    });

    test('keeps the minimum size', () {
      final result = CropGeometry.applyDrag(
        start: const CropRect(left: 400, top: 300, right: 500, bottom: 400),
        handle: CropHandle.right,
        screenDelta: const Offset(-500, 0),
        viewport: viewport,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(result.width, greaterThanOrEqualTo(CropGeometry.defaultMinSize));
    });
  });

  group('CropGeometry aspect ratio lock', () {
    final start = const CropRect(left: 100, top: 100, right: 900, bottom: 700);

    test('preserves the requested aspect ratio', () {
      final result = CropGeometry.applyDrag(
        start: start,
        handle: CropHandle.bottomRight,
        screenDelta: const Offset(60, 10),
        viewport: viewport,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspectRatio: 1,
      );
      expect(result.width, closeTo(result.height, 1.0));
    });

    test('stays inside the image with an aspect ratio locked', () {
      final result = CropGeometry.applyDrag(
        start: start,
        handle: CropHandle.topLeft,
        screenDelta: const Offset(-5000, -5000),
        viewport: viewport,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspectRatio: 4 / 3,
      );
      expect(result.left, greaterThanOrEqualTo(0));
      expect(result.top, greaterThanOrEqualTo(0));
      expect(result.right, lessThanOrEqualTo(imageWidth.toDouble()));
      expect(result.bottom, lessThanOrEqualTo(imageHeight.toDouble()));
      expect(result.width / result.height, closeTo(4 / 3, 1e-6));
    });

    test('shrinks smoothly when dragging corner inwards with aspect ratio locked', () {
      // Regression test: corner dragging must not lock up or refuse to shrink
      const squareStart = CropRect(left: 100, top: 100, right: 700, bottom: 700);
      final result = CropGeometry.applyDrag(
        start: squareStart,
        handle: CropHandle.bottomRight,
        screenDelta: const Offset(-80, -30),
        viewport: viewport,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspectRatio: 1,
      );
      expect(result.width, closeTo(result.height, 1e-6));
      expect(result.width, lessThan(squareStart.width));
      expect(result.height, lessThan(squareStart.height));
      expect(result.left, squareStart.left);
      expect(result.top, squareStart.top);
    });

    test('shrinks smoothly when dragging topLeft corner inwards with aspect ratio locked', () {
      final result = CropGeometry.applyDrag(
        start: start,
        handle: CropHandle.topLeft,
        screenDelta: const Offset(40, 20),
        viewport: viewport,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspectRatio: 4 / 3,
      );
      expect(result.width / result.height, closeTo(4 / 3, 1e-6));
      expect(result.width, lessThan(start.width));
      expect(result.height, lessThan(start.height));
      expect(result.right, start.right);
      expect(result.bottom, start.bottom);
    });
  });

  group('CropGeometry edge segment hit-testing', () {
    final crop = const CropRect(left: 100, top: 100, right: 900, bottom: 700);

    test('detects edges along the entire boundary, not just at the center', () {
      // Top edge at 25% across and 75% across
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(300, 100)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.top,
      );
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(700, 100)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.top,
      );

      // Bottom edge at 30% and 70% across
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(350, 700)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.bottom,
      );
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(650, 700)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.bottom,
      );

      // Left edge at 25% and 75% down
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(100, 250)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.left,
      );
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(100, 550)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.left,
      );

      // Right edge at 25% and 75% down
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(900, 250)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.right,
      );
      expect(
        CropGeometry.hitTest(
          screenPosition: viewport.toScreen(const Offset(900, 550)),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.right,
      );
    });

    test('corner hit targets have priority and generous touch radius', () {
      // Offset slightly away from corner (15px screen delta) still hits the corner
      final cornerPos = viewport.toScreen(const Offset(100, 100));
      expect(
        CropGeometry.hitTest(
          screenPosition: cornerPos + const Offset(15, 15),
          crop: crop,
          viewport: viewport,
        ),
        CropHandle.topLeft,
      );
    });
  });

  group('CropViewport with padding (unclipped preview)', () {
    const paddedViewport = CropViewport(
      imageSize: Size(1000, 800),
      viewportSize: Size(500, 400),
      padding: EdgeInsets.all(20),
    );

    test('insets image so corners are never cropped by preview boundary', () {
      final fullCrop = CropRect.full(1000, 800);
      final screenRect = paddedViewport.cropToScreen(fullCrop);

      // Must be at least 20px away from the widget's outer boundary
      expect(screenRect.left, greaterThanOrEqualTo(20));
      expect(screenRect.top, greaterThanOrEqualTo(20));
      expect(screenRect.right, lessThanOrEqualTo(500 - 20));
      expect(screenRect.bottom, lessThanOrEqualTo(400 - 20));
    });
  });
}
