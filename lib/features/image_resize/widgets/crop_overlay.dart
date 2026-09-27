import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/crop_geometry.dart';

/// Interactive crop editor.
///
/// Gesture ownership is deliberately exclusive so the reported bug (dragging a
/// crop handle also moving the image/workspace) cannot happen:
///
///  * dragging a handle changes **only** that crop boundary;
///  * dragging inside the crop rectangle moves the rectangle;
///  * dragging outside the rectangle pans the image;
///  * a two-finger pinch zooms the image around the pinch focal point.
///
/// All crop math happens in original image pixel coordinates through
/// [CropGeometry] / [CropViewport], so the result stays correct at any zoom,
/// pan, or device size.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.crop,
    this.aspectRatio,
    this.flipH = false,
    this.flipV = false,
    this.minSize = CropGeometry.defaultMinSize,
    this.onCropChanged,
    this.onCropCommitted,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;

  /// Current crop rectangle in original image pixels.
  final CropRect crop;

  /// Locked width/height ratio, or null for free-form cropping.
  final double? aspectRatio;

  final bool flipH;
  final bool flipV;
  final double minSize;

  /// Called continuously while the crop rectangle changes.
  final ValueChanged<CropRect>? onCropChanged;

  /// Called once when a crop gesture finishes.
  final ValueChanged<CropRect>? onCropCommitted;

  @override
  State<CropOverlay> createState() => CropOverlayState();
}

class CropOverlayState extends State<CropOverlay> {
  /// Key on the image layer, used by tests to assert its on-screen footprint.
  static const Key imageLayerKey = Key('crop-image-layer');

  late CropRect _crop;
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  double _scaleAtGestureStart = 1.0;
  CropHandle? _activeHandle;
  bool _isZooming = false;
  Size _viewportSize = Size.zero;

  /// Current zoom factor (1.0 = fitted). Exposed for tests and badges.
  double get scale => _scale;

  /// Current fit/zoom/pan model. Exposed for tests.
  @visibleForTesting
  CropViewport get viewport => _viewport;

  @override
  void initState() {
    super.initState();
    _crop = widget.crop;
  }

  @override
  void didUpdateWidget(covariant CropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // While a gesture is in progress the local rectangle wins; otherwise the
    // parent (e.g. the numeric X/Y/W/H fields) is the source of truth.
    if (_activeHandle == null && !_isZooming) {
      _crop = widget.crop;
    }
    if (oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _scale = 1.0;
      _pan = Offset.zero;
    }
  }

  CropViewport get _viewport => CropViewport(
        imageSize: Size(
          widget.imageWidth.toDouble(),
          widget.imageHeight.toDouble(),
        ),
        viewportSize: _viewportSize,
        scale: _scale,
        pan: _pan,
      );

  void resetZoom() {
    setState(() {
      _scale = 1.0;
      _pan = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAtGestureStart = _scale;
    _isZooming = false;
    if (_viewportSize.isEmpty) {
      _activeHandle = null;
      return;
    }
    _activeHandle = CropGeometry.hitTest(
      screenPosition: details.localFocalPoint,
      crop: _crop,
      viewport: _viewport,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_viewportSize.isEmpty) return;

    if (details.pointerCount >= 2) {
      // Pinch: zoom the image, never touch the crop rectangle.
      _isZooming = true;
      _activeHandle = null;
      final target = (_scaleAtGestureStart * details.scale).clamp(1.0, 8.0);
      final zoomed = _viewport
          .zoomAround(details.localFocalPoint, target)
          .clamped();
      setState(() {
        _scale = zoomed.scale;
        _pan = zoomed.pan;
      });
      return;
    }

    if (_isZooming) return;

    final handle = _activeHandle;
    if (handle == null) {
      // Empty space (or outside the crop box): pan the image.
      final panned = _viewport
          .copyWith(pan: _pan + details.focalPointDelta)
          .clamped();
      setState(() {
        _pan = panned.pan;
      });
      return;
    }

    final next = CropGeometry.applyDrag(
      start: _crop,
      handle: handle,
      screenDelta: details.focalPointDelta,
      viewport: _viewport,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      aspectRatio: widget.aspectRatio,
      minSize: widget.minSize,
    );
    setState(() => _crop = next);
    widget.onCropChanged?.call(next);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_activeHandle != null) {
      widget.onCropCommitted?.call(_crop);
    }
    _activeHandle = null;
    _isZooming = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        if (_viewportSize.isEmpty ||
            widget.imageWidth <= 0 ||
            widget.imageHeight <= 0) {
          return const SizedBox.expand();
        }

        final viewport = _viewport;

        // The image is positioned and sized explicitly for its on-screen
        // footprint. Scaling a natural-size subtree with a matrix does not work
        // here: a Stack forces its children to the frame size, so the image
        // would be laid out at the frame and then shrunk by the fit factor,
        // rendering tiny in the corner instead of filling the frame.
        final onScreenWidth = widget.imageWidth * viewport.effectiveScale;
        final onScreenHeight = widget.imageHeight * viewport.effectiveScale;

        // Decode just enough pixels for the visible size (up to 3x zoom) so a
        // large photo never costs a full-resolution decode for a preview.
        final devicePixelRatio =
            MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
        final cacheWidth = math.min(
          widget.imageWidth,
          (onScreenWidth * devicePixelRatio).ceil().clamp(1, 8192),
        );
        final cacheHeight = math.min(
          widget.imageHeight,
          (onScreenHeight * devicePixelRatio).ceil().clamp(1, 8192),
        );

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTap: resetZoom,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: viewport.translation.dx,
                  top: viewport.translation.dy,
                  width: onScreenWidth,
                  height: onScreenHeight,
                  child: Transform.scale(
                    scaleX: widget.flipH ? -1.0 : 1.0,
                    scaleY: widget.flipV ? -1.0 : 1.0,
                    child: Image.memory(
                      key: CropOverlayState.imageLayerKey,
                      widget.imageBytes,
                      fit: BoxFit.fill,
                      cacheWidth: cacheWidth,
                      cacheHeight: cacheHeight,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (context, error, stackTrace) => ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                CustomPaint(
                  painter: CropOverlayPainter(
                    cropScreenRect: viewport.cropToScreen(_crop),
                    accent: const Color(0xFF8B1BFF),
                  ),
                ),
                if (_scale > 1.02)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: IgnorePointer(
                      child: _ZoomBadge(
                        scale: _scale,
                        onReset: resetZoom,
                      ),
                    ),
                  ),
                if (_activeHandle == null && _scale <= 1.02)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Drag edges to crop · pinch to zoom',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.scale, required this.onReset});

  final double scale;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onReset,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_out_map_rounded,
                  size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                '${scale.toStringAsFixed(1)}×  reset',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the dim mask, border, rule-of-thirds grid and drag handles.
class CropOverlayPainter extends CustomPainter {
  const CropOverlayPainter({
    required this.cropScreenRect,
    required this.accent,
    this.handleRadius = 12,
    this.edgeBarLong = 44,
    this.edgeBarShort = 16,
  });

  final Rect cropScreenRect;
  final Color accent;
  final double handleRadius;
  final double edgeBarLong;
  final double edgeBarShort;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final crop = cropScreenRect.intersect(fullRect);
    if (crop.isEmpty) return;

    // Dim everything outside the crop rectangle.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(fullRect),
        Path()..addRect(crop),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // Border.
    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Rule of thirds.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final factor in <double>[1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(crop.left + crop.width * factor, crop.top),
        Offset(crop.left + crop.width * factor, crop.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * factor),
        Offset(crop.right, crop.top + crop.height * factor),
        grid,
      );
    }

    // Edge bars.
    final barFill = Paint()..color = Colors.white;
    final barStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    void bar(Offset centre, double width, double height) {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: width, height: height),
        const Radius.circular(8),
      );
      canvas.drawRRect(rrect, barFill);
      canvas.drawRRect(rrect, barStroke);
    }

    bar(Offset(crop.center.dx, crop.top), edgeBarLong, edgeBarShort);
    bar(Offset(crop.center.dx, crop.bottom), edgeBarLong, edgeBarShort);
    bar(Offset(crop.left, crop.center.dy), edgeBarShort, edgeBarLong);
    bar(Offset(crop.right, crop.center.dy), edgeBarShort, edgeBarLong);

    // Corner circles, drawn last so they sit above the bars.
    final cornerFill = Paint()..color = Colors.white;
    final cornerStroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final corner in <Offset>[
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawCircle(corner, handleRadius, cornerFill);
      canvas.drawCircle(corner, handleRadius, cornerStroke);
    }
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) =>
      oldDelegate.cropScreenRect != cropScreenRect ||
      oldDelegate.accent != accent;
}
