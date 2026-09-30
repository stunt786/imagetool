import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Which part of the crop rectangle a gesture grabbed.
enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,

  /// Inside the rectangle: moves it without resizing.
  move,
}

/// Crop rectangle in **original image pixel coordinates**.
///
/// This is the single source of truth for cropping. Screen coordinates are
/// only ever derived from it through [CropViewport], which keeps the crop
/// correct after zooming, panning, rotating or resizing the device.
@immutable
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// The whole image.
  static CropRect full(num imageWidth, num imageHeight) => CropRect(
        left: 0,
        top: 0,
        right: imageWidth.toDouble(),
        bottom: imageHeight.toDouble(),
      );

  double get width => right - left;

  double get height => bottom - top;

  bool get isEmpty => width <= 0 || height <= 0;

  Size get size => Size(width, height);

  Offset get topLeft => Offset(left, top);

  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);

  /// Integer rectangle used when the crop is applied to the bitmap.
  ({int x, int y, int width, int height}) toPixelRect({
    required int imageWidth,
    required int imageHeight,
  }) {
    final x = left.floor().clamp(0, math.max(0, imageWidth - 1)).toInt();
    final y = top.floor().clamp(0, math.max(0, imageHeight - 1)).toInt();
    var w = width.round().clamp(1, math.max(1, imageWidth - x)).toInt();
    var h = height.round().clamp(1, math.max(1, imageHeight - y)).toInt();
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    return (x: x, y: y, width: w, height: h);
  }

  CropRect copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    return CropRect(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'CropRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${right.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)})';
}

/// Converts between screen (viewport) coordinates and original image pixels
/// for a preview that is fitted, zoomed and panned.
///
/// The transform is `screen = imagePixels * effectiveScale + translation`,
/// so it is trivially invertible and safe to use for gesture math.
@immutable
class CropViewport {
  const CropViewport({
    required this.imageSize,
    required this.viewportSize,
    this.scale = 1.0,
    this.pan = Offset.zero,
    this.padding = EdgeInsets.zero,
  });

  /// Original image size in pixels.
  final Size imageSize;

  /// Size of the preview box on screen.
  final Size viewportSize;

  /// User zoom; 1.0 means "fitted to the viewport".
  final double scale;

  /// User pan in screen pixels, applied after fitting.
  final Offset pan;

  /// Padding around the image inside the viewport to keep handles visible and unclipped.
  final EdgeInsets padding;

  /// Available size for the image inside the viewport.
  Size get availableSize => Size(
        math.max(0.0, viewportSize.width - padding.horizontal),
        math.max(0.0, viewportSize.height - padding.vertical),
      );

  /// Scale that fits the image inside the available viewport area.
  double get fitScale {
    if (imageSize.width <= 0 || imageSize.height <= 0) return 1;
    final avail = availableSize;
    if (avail.width <= 0 || avail.height <= 0) return 1;
    return math.min(
      avail.width / imageSize.width,
      avail.height / imageSize.height,
    );
  }

  /// Image pixels -> screen pixels.
  double get effectiveScale => fitScale * scale;

  Size get fittedSize => Size(
        imageSize.width * fitScale,
        imageSize.height * fitScale,
      );

  /// Top-left of the fitted image inside the viewport before panning.
  Offset get fittedOrigin => Offset(
        padding.left + (availableSize.width - fittedSize.width) / 2,
        padding.top + (availableSize.height - fittedSize.height) / 2,
      );

  /// Top-left of the transformed image in viewport coordinates.
  Offset get translation => fittedOrigin + pan;

  Offset toImage(Offset screen) {
    final s = effectiveScale;
    if (s <= 0) return Offset.zero;
    return (screen - translation) / s;
  }

  Offset toScreen(Offset imagePoint) => imagePoint * effectiveScale + translation;

  Offset imageDeltaToScreen(Offset imageDelta) => imageDelta * effectiveScale;

  Offset screenDeltaToImage(Offset screenDelta) {
    final s = effectiveScale;
    if (s <= 0) return Offset.zero;
    return screenDelta / s;
  }

  Rect cropToScreen(CropRect crop) {
    final tl = toScreen(crop.topLeft);
    final br = toScreen(Offset(crop.right, crop.bottom));
    return Rect.fromPoints(tl, br);
  }

  /// Returns a copy zoomed to [newScale] while keeping [focalPoint] (screen
  /// coordinates) visually stationary.
  CropViewport zoomAround(Offset focalPoint, double newScale) {
    final clamped = newScale.clamp(1.0, 8.0);
    if (clamped == scale) return this;
    final ratio = clamped / scale;
    // translation' = focal - (focal - translation) * ratio
    final newTranslation = focalPoint - (focalPoint - translation) * ratio;
    final newPan = newTranslation - fittedOrigin;
    return CropViewport(
      imageSize: imageSize,
      viewportSize: viewportSize,
      scale: clamped,
      pan: newPan,
      padding: padding,
    );
  }

  /// Keeps the (possibly zoomed/panned) image from drifting completely out of
  /// the viewport.
  CropViewport clamped() {
    if (scale <= 1.0) {
      return CropViewport(
        imageSize: imageSize,
        viewportSize: viewportSize,
        scale: 1.0,
        pan: Offset.zero,
        padding: padding,
      );
    }
    final scaledW = fittedSize.width * scale;
    final scaledH = fittedSize.height * scale;
    // Allow panning only within the overflow created by zooming.
    final maxDx = math.max(0.0, (scaledW - availableSize.width) / 2);
    final maxDy = math.max(0.0, (scaledH - availableSize.height) / 2);
    return CropViewport(
      imageSize: imageSize,
      viewportSize: viewportSize,
      scale: scale,
      pan: Offset(
        pan.dx.clamp(-maxDx, maxDx),
        pan.dy.clamp(-maxDy, maxDy),
      ),
      padding: padding,
    );
  }

  CropViewport copyWith({
    double? scale,
    Offset? pan,
    EdgeInsets? padding,
  }) =>
      CropViewport(
        imageSize: imageSize,
        viewportSize: viewportSize,
        scale: scale ?? this.scale,
        pan: pan ?? this.pan,
        padding: padding ?? this.padding,
      );
}

/// Pure crop geometry. Kept free of widgets so it can be unit tested.
abstract final class CropGeometry {
  static const double defaultMinSize = 24;

  /// Resolves which handle (if any) is under [screenPosition].
  ///
  /// Corners have priority with a generous hit zone, and each edge boundary
  /// can be dragged anywhere along its entire line segment.
  static CropHandle? hitTest({
    required Offset screenPosition,
    required CropRect crop,
    required CropViewport viewport,
    double touchSlop = 28,
  }) {
    if (crop.isEmpty) return null;
    final tl = viewport.toScreen(crop.topLeft);
    final tr = viewport.toScreen(Offset(crop.right, crop.top));
    final bl = viewport.toScreen(Offset(crop.left, crop.bottom));
    final br = viewport.toScreen(Offset(crop.right, crop.bottom));

    final corners = <CropHandle, Offset>{
      CropHandle.topLeft: tl,
      CropHandle.topRight: tr,
      CropHandle.bottomLeft: bl,
      CropHandle.bottomRight: br,
    };

    // 1. Corners first: generous touch target (corners win ties and have larger grab zones).
    final cornerSlop = math.max(touchSlop, 36.0);
    CropHandle? closestCorner;
    double minCornerDist = double.infinity;
    for (final entry in corners.entries) {
      final d = (screenPosition - entry.value).distance;
      if (d <= cornerSlop && d < minCornerDist) {
        minCornerDist = d;
        closestCorner = entry.key;
      }
    }
    if (closestCorner != null) {
      return closestCorner;
    }

    // 2. Entire edge segments: allow dragging from anywhere along each edge.
    final leftX = math.min(tl.dx, tr.dx);
    final rightX = math.max(tl.dx, tr.dx);
    final topY = math.min(tl.dy, bl.dy);
    final bottomY = math.max(tl.dy, bl.dy);

    final px = screenPosition.dx;
    final py = screenPosition.dy;

    // Top edge segment
    final clampedTopX = px.clamp(leftX, rightX);
    final topDist = (screenPosition - Offset(clampedTopX, topY)).distance;

    // Bottom edge segment
    final clampedBottomX = px.clamp(leftX, rightX);
    final bottomDist = (screenPosition - Offset(clampedBottomX, bottomY)).distance;

    // Left edge segment
    final clampedLeftY = py.clamp(topY, bottomY);
    final leftDist = (screenPosition - Offset(leftX, clampedLeftY)).distance;

    // Right edge segment
    final clampedRightY = py.clamp(topY, bottomY);
    final rightDist = (screenPosition - Offset(rightX, clampedRightY)).distance;

    final edgeSlop = math.max(touchSlop, 26.0);
    double minEdgeDist = edgeSlop;
    CropHandle? closestEdge;

    if (topDist <= minEdgeDist) {
      minEdgeDist = topDist;
      closestEdge = CropHandle.top;
    }
    if (bottomDist <= minEdgeDist) {
      minEdgeDist = bottomDist;
      closestEdge = CropHandle.bottom;
    }
    if (leftDist <= minEdgeDist) {
      minEdgeDist = leftDist;
      closestEdge = CropHandle.left;
    }
    if (rightDist <= minEdgeDist) {
      minEdgeDist = rightDist;
      closestEdge = CropHandle.right;
    }

    if (closestEdge != null) {
      return closestEdge;
    }

    // 3. Inside the rectangle: moves it without resizing.
    if (viewport.cropToScreen(crop).contains(screenPosition)) {
      return CropHandle.move;
    }
    return null;
  }

  /// Applies a gesture to [start], returning the new crop rectangle.
  ///
  /// [screenDelta] is converted to image pixels internally, so a drag always
  /// tracks the finger exactly, at any zoom level.
  ///
  /// Dragging an edge handle changes only that edge (unless an [aspectRatio]
  /// is locked, in which case the perpendicular dimension follows).
  static CropRect applyDrag({
    required CropRect start,
    required CropHandle handle,
    required Offset screenDelta,
    required CropViewport viewport,
    required int imageWidth,
    required int imageHeight,
    double? aspectRatio,
    double minSize = defaultMinSize,
  }) {
    final delta = viewport.screenDeltaToImage(screenDelta);
    final dx = delta.dx;
    final dy = delta.dy;

    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;

    switch (handle) {
      case CropHandle.move:
        final w = start.width;
        final h = start.height;
        left = (start.left + dx).clamp(0.0, math.max(0.0, imageWidth - w));
        top = (start.top + dy).clamp(0.0, math.max(0.0, imageHeight - h));
        right = left + w;
        bottom = top + h;
        return CropRect(left: left, top: top, right: right, bottom: bottom);
      case CropHandle.topLeft:
        left += dx;
        top += dy;
        break;
      case CropHandle.topRight:
        right += dx;
        top += dy;
        break;
      case CropHandle.bottomLeft:
        left += dx;
        bottom += dy;
        break;
      case CropHandle.bottomRight:
        right += dx;
        bottom += dy;
        break;
      case CropHandle.top:
        top += dy;
        break;
      case CropHandle.bottom:
        bottom += dy;
        break;
      case CropHandle.left:
        left += dx;
        break;
      case CropHandle.right:
        right += dx;
        break;
    }

    // Keep inside the image.
    left = left.clamp(0.0, imageWidth.toDouble());
    right = right.clamp(0.0, imageWidth.toDouble());
    top = top.clamp(0.0, imageHeight.toDouble());
    bottom = bottom.clamp(0.0, imageHeight.toDouble());

    // Enforce the minimum size by pushing back the edge that moved.
    final movesLeft = handle == CropHandle.left ||
        handle == CropHandle.topLeft ||
        handle == CropHandle.bottomLeft;
    final movesTop = handle == CropHandle.top ||
        handle == CropHandle.topLeft ||
        handle == CropHandle.topRight;

    if (right - left < minSize) {
      if (movesLeft) {
        left = math.max(0.0, right - minSize);
      } else {
        right = math.min(imageWidth.toDouble(), left + minSize);
      }
    }
    if (bottom - top < minSize) {
      if (movesTop) {
        top = math.max(0.0, bottom - minSize);
      } else {
        bottom = math.min(imageHeight.toDouble(), top + minSize);
      }
    }

    var result = CropRect(left: left, top: top, right: right, bottom: bottom);

    if (aspectRatio != null && aspectRatio > 0 && !result.isEmpty) {
      result = _applyAspectRatio(
        result: result,
        handle: handle,
        start: start,
        aspectRatio: aspectRatio,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        minSize: minSize,
      );
    }

    return result;
  }

  static CropRect _applyAspectRatio({
    required CropRect result,
    required CropHandle handle,
    required CropRect start,
    required double aspectRatio,
    required int imageWidth,
    required int imageHeight,
    required double minSize,
  }) {
    final movesLeft = handle == CropHandle.left ||
        handle == CropHandle.topLeft ||
        handle == CropHandle.bottomLeft;
    final movesRight = handle == CropHandle.right ||
        handle == CropHandle.topRight ||
        handle == CropHandle.bottomRight;
    final movesTop = handle == CropHandle.top ||
        handle == CropHandle.topLeft ||
        handle == CropHandle.topRight;
    final movesBottom = handle == CropHandle.bottom ||
        handle == CropHandle.bottomLeft ||
        handle == CropHandle.bottomRight;
    final isCorner = (movesLeft || movesRight) && (movesTop || movesBottom);

    // Anchor: the edges the gesture does not touch stay put.
    final anchorX = movesLeft ? start.right : start.left;
    final anchorY = movesTop ? start.bottom : start.top;

    double w;
    double h;
    if (isCorner) {
      // Follow the dominant gesture direction so shrinking and expanding both feel natural
      final dw = (result.width - start.width).abs();
      final dh = (result.height - start.height).abs();
      if (dw >= dh * aspectRatio) {
        w = result.width;
        h = w / aspectRatio;
      } else {
        h = result.height;
        w = h * aspectRatio;
      }
    } else if (movesLeft || movesRight) {
      w = result.width;
      h = w / aspectRatio;
    } else {
      h = result.height;
      w = h * aspectRatio;
    }

    // Fit into the space available from the anchor.
    final availableW =
        movesLeft ? anchorX : (imageWidth - anchorX).toDouble();
    final availableH =
        movesTop ? anchorY : (imageHeight - anchorY).toDouble();
    final maxW = math.max(minSize, availableW);
    final maxH = math.max(minSize, availableH);
    final fit = math.min(maxW / math.max(w, 0.001), maxH / math.max(h, 0.001));
    if (fit < 1) {
      w *= fit;
      h *= fit;
    }
    w = math.max(minSize, w);
    h = math.max(minSize, h);

    double left;
    double right;
    double top;
    double bottom;

    if (isCorner) {
      left = movesLeft ? anchorX - w : anchorX;
      right = left + w;
      top = movesTop ? anchorY - h : anchorY;
      bottom = top + h;
    } else if (movesLeft || movesRight) {
      left = movesLeft ? anchorX - w : anchorX;
      right = left + w;
      // Keep the perpendicular axis centred.
      final centre = (result.top + result.bottom) / 2;
      top = centre - h / 2;
      bottom = centre + h / 2;
    } else {
      top = movesTop ? anchorY - h : anchorY;
      bottom = top + h;
      final centre = (result.left + result.right) / 2;
      left = centre - w / 2;
      right = centre + w / 2;
    }

    // Final nudge back inside the image.
    if (left < 0) {
      right -= left;
      left = 0;
    }
    if (top < 0) {
      bottom -= top;
      top = 0;
    }
    if (right > imageWidth) {
      left -= right - imageWidth;
      right = imageWidth.toDouble();
    }
    if (bottom > imageHeight) {
      top -= bottom - imageHeight;
      bottom = imageHeight.toDouble();
    }
    left = math.max(0, left);
    top = math.max(0, top);

    return CropRect(left: left, top: top, right: right, bottom: bottom);
  }
}
