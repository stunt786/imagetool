import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../models/collage_state.dart';
import '../notifiers/collage_notifier.dart';
import 'collage_text_dialog.dart';

class CollageCanvas extends ConsumerStatefulWidget {
  const CollageCanvas({super.key});

  @override
  ConsumerState<CollageCanvas> createState() => _CollageCanvasState();
}

class _CollageCanvasState extends ConsumerState<CollageCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  int? _dragStartIndex;
  int? _dragHoverIndex;
  Offset? _dragOffset;
  double _currentScale = 1.0;
  double _initialScale = 1.0;
  int? _pinchSlotIndex;
  int? _panSlotIndex;
  Offset _panPixelStart = Offset.zero;
  Offset _panPixelDelta = Offset.zero;
  bool _isPanning = false;
  static const double _panThreshold = 4.0;
  String? _activeTextLayerId;
  double _initialTextRotation = 0.0;
  double _initialTextScale = 1.0;
  double _textResizeStartDist = 0.0;
  double _textResizeStartScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return _buildCanvas(context);
  }

  Widget _buildCanvas(BuildContext context) {
    final state = ref.watch(collageProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final aspectRatio = state.canvasHeight / state.canvasWidth;
        
        var width = maxWidth;
        var height = width * aspectRatio;
        
        if (height > maxHeight) {
          height = maxHeight;
          width = height / aspectRatio;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              (state.previewWidth != width || state.previewHeight != height)) {
            ref.read(collageProvider.notifier).setPreviewSize(width, height);
          }
        });

        return Center(
          child: RepaintBoundary(
            child: Listener(
            key: _canvasKey,
            onPointerMove: _dragStartIndex != null ? _handlePointerMove : null,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: state.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    ...List.generate(state.layout.slotCount, (index) {
                      return _buildSlot(context, state, index, width, height);
                    }),
                    ...state.textLayers.where((l) => !l.isEmpty).map(
                      (layer) => _buildTextLayerOverlay(context, state, layer, width, height),
                    ),
                    if (state.captionText != null && state.captionText!.isNotEmpty)
                      Positioned(
                        left: state.captionNormalizedOffset.dx * width,
                        top: state.captionNormalizedOffset.dy * height,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: Transform.scale(
                            scale: state.captionScale,
                            child: Text(
                              state.captionText!,
                              style: TextStyle(
                                color: state.captionColor,
                                fontSize: state.captionSize,
                                fontFamily: state.captionFontFamily,
                                shadows: const [
                                  Shadow(
                                    blurRadius: 4,
                                    color: Colors.black54,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_dragStartIndex != null && _dragOffset != null)
                      _buildDragIndicator(context, state, width, height),
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildSlot(
    BuildContext context,
    CollageState state,
    int index,
    double canvasWidth,
    double canvasHeight,
  ) {
    final rect = state.layout.slotRects[index];
    final gap = state.gap;

    final left = rect.left * canvasWidth + gap;
    final top = rect.top * canvasHeight + gap;
    final width = rect.width * canvasWidth - gap * 2;
    final height = rect.height * canvasHeight - gap * 2;

    final slot = state.images[index];
    final isDragSource = _dragStartIndex == index;
    final isDragTarget = _dragHoverIndex == index && _dragStartIndex != index;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: () => _handleSlotTap(context, index),
          onScaleStart: (details) => _handleScaleStart(index, details, width, height),
          onScaleUpdate: (details) => _handleScaleUpdate(index, details, width, height),
          onScaleEnd: (details) => _handleScaleEnd(index, width, height),
          onLongPressStart: (details) => _handleLongPressStart(index, details),
          onLongPressEnd: (details) => _handleLongPressEnd(index),
          behavior: HitTestBehavior.translucent,
          child: Container(
            decoration: BoxDecoration(
              color: isDragSource
                  ? Colors.transparent
                  : isDragTarget
                      ? Colors.blue.withValues(alpha: 0.2)
                      : slot.hasImage
                          ? Colors.transparent
                          : const Color(0xFFD6E4FF),
              border: Border.all(
                color: isDragTarget
                    ? Colors.blue
                    : isDragSource
                        ? Colors.blue.withValues(alpha: 0.5)
                        : slot.hasImage
                            ? Colors.transparent
                            : const Color(0xFF5B4DFF).withValues(alpha: 0.3),
                width: isDragTarget ? 3 : isDragSource ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(state.cornerRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(state.cornerRadius),
              child: slot.hasImage && !isDragSource
                ? _buildImageContent(slot, width, height, index)
                : slot.hasImage && isDragSource
                    ? Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 40,
                          color: Colors.blue.withValues(alpha: 0.6),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.add_circle,
                          size: 40,
                          color: Color(0xFF5B4DFF),
                        ),
                      ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildImageContent(CollageImageSlot slot, double width, double height, int index) {
    final isPinching = _pinchSlotIndex == index;
    final isPanning = _panSlotIndex == index;
    final scale = isPinching ? _currentScale : slot.scale;
    final pixelOffsetX = isPanning ? (_panPixelStart.dx + _panPixelDelta.dx) : slot.offsetX * width;
    final pixelOffsetY = isPanning ? (_panPixelStart.dy + _panPixelDelta.dy) : slot.offsetY * height;

    final maxOffsetX = scale > 1.0 ? (width * (scale - 1.0)) / 2 : 0.0;
    final maxOffsetY = scale > 1.0 ? (height * (scale - 1.0)) / 2 : 0.0;
    final clampedOffsetX = pixelOffsetX.clamp(-maxOffsetX, maxOffsetX);
    final clampedOffsetY = pixelOffsetY.clamp(-maxOffsetY, maxOffsetY);

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: Transform(
              transform: Matrix4.identity()
                ..translateByVector3(
                    vec.Vector3(clampedOffsetX, clampedOffsetY, 0))
                ..scaleByDouble(scale, scale, 1.0, 1.0),
              alignment: Alignment.center,
              child: RotatedBox(
                quarterTurns: ((slot.rotation / 90).round() % 4 + 4) % 4,
                child: Image.memory(
                  slot.imageBytes!,
                  fit: slot.fitMode == ImageFitMode.cover
                      ? BoxFit.cover
                      : slot.fitMode == ImageFitMode.contain
                          ? BoxFit.contain
                          : BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
        if (slot.fitMode != ImageFitMode.contain)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                slot.fitMode == ImageFitMode.cover ? '⊡' : '▣',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        if (slot.scale > 1.0)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(slot.scale * 100).toInt()}%',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDragIndicator(
    BuildContext context,
    CollageState state,
    double canvasWidth,
    double canvasHeight,
  ) {
    if (_dragOffset == null || _dragStartIndex == null) return const SizedBox.shrink();

    final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null) return const SizedBox.shrink();

    final canvasLocalPosition = canvasBox.globalToLocal(_dragOffset!);
    final dragSlot = state.images[_dragStartIndex!];

    return Positioned(
      left: canvasLocalPosition.dx - 30,
      top: canvasLocalPosition.dy - 30,
      child: IgnorePointer(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.blue,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: dragSlot.hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    dragSlot.imageBytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    cacheHeight: 240,
                    filterQuality: FilterQuality.low,
                    opacity: const AlwaysStoppedAnimation(0.7),
                  ),
                )
              : const Center(
                  child: Icon(Icons.drag_indicator, color: Colors.blue),
                ),
        ),
      ),
    );
  }

  void _handleSlotTap(BuildContext context, int index) {
    final state = ref.read(collageProvider);
    if (state.images[index].hasImage) {
      _showSlotOptions(context, index);
    } else {
      ref.read(collageProvider.notifier).addImageToSlot(context, index);
    }
  }

  void _showSlotOptions(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SlotOptionsSheet(slotIndex: index),
    );
  }

  void _handleScaleStart(int index, ScaleStartDetails details, double slotWidth, double slotHeight) {
    final state = ref.read(collageProvider);
    if (!state.images[index].hasImage) return;

    if (details.pointerCount == 2) {
      _pinchSlotIndex = index;
      _initialScale = state.images[index].scale;
      _currentScale = _initialScale;
    } else if (state.images[index].scale > 1.0) {
      _panSlotIndex = index;
      _panPixelStart = Offset(
        state.images[index].offsetX * slotWidth,
        state.images[index].offsetY * slotHeight,
      );
      _panPixelDelta = Offset.zero;
      _isPanning = false;
    }
  }

  void _handleScaleUpdate(int index, ScaleUpdateDetails details, double slotWidth, double slotHeight) {
    final state = ref.read(collageProvider);
    final slot = state.images[index];
    if (!slot.hasImage) return;

    if (_pinchSlotIndex == index && details.pointerCount == 2) {
      _currentScale = (_initialScale * details.scale).clamp(1.0, 5.0);
      ref.read(collageProvider.notifier).setScale(index, _currentScale);
    } else if (_panSlotIndex == index && details.pointerCount == 1 && slot.scale > 1.0) {
      final totalDelta = details.focalPointDelta.distance;
      if (!_isPanning && totalDelta > _panThreshold) {
        _isPanning = true;
      }

      if (_isPanning) {
        final scale = slot.scale;
        final maxOffsetX = (slotWidth * (scale - 1.0)) / 2;
        final maxOffsetY = (slotHeight * (scale - 1.0)) / 2;

        final newX = (_panPixelStart.dx + _panPixelDelta.dx + details.focalPointDelta.dx).clamp(-maxOffsetX, maxOffsetX);
        final newY = (_panPixelStart.dy + _panPixelDelta.dy + details.focalPointDelta.dy).clamp(-maxOffsetY, maxOffsetY);

        setState(() {
          _panPixelDelta = Offset(newX - _panPixelStart.dx, newY - _panPixelStart.dy);
        });
      }
    }
  }

  void _handleScaleEnd(int index, double slotWidth, double slotHeight) {
    if (_pinchSlotIndex == index) {
      _pinchSlotIndex = null;
      _currentScale = 1.0;
      _initialScale = 1.0;
    } else if (_panSlotIndex == index) {
      if (_isPanning) {
        final finalOffsetX = (_panPixelStart.dx + _panPixelDelta.dx) / (slotWidth > 0 ? slotWidth : 1);
        final finalOffsetY = (_panPixelStart.dy + _panPixelDelta.dy) / (slotHeight > 0 ? slotHeight : 1);

        ref.read(collageProvider.notifier).setOffset(index, finalOffsetX, finalOffsetY);
      }

      setState(() {
        _panSlotIndex = null;
        _panPixelStart = Offset.zero;
        _panPixelDelta = Offset.zero;
        _isPanning = false;
      });
    }
  }
  void _handleLongPressStart(int index, LongPressStartDetails details) {
    final state = ref.read(collageProvider);
    if (state.images[index].hasImage) {
      setState(() {
        _dragStartIndex = index;
        _dragOffset = details.globalPosition;
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dragStartIndex == null) return;

    final state = ref.read(collageProvider);
    final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null) return;

    final localPosition = canvasBox.globalToLocal(event.position);
    final canvasWidth = canvasBox.size.width;
    final canvasHeight = canvasBox.size.height;
    
    int? targetIndex;

    for (int i = 0; i < state.layout.slotCount; i++) {
      if (i == _dragStartIndex) continue;
      
      final rect = state.layout.slotRects[i];
      final gap = state.gap;
      
      final slotLeft = rect.left * canvasWidth + gap;
      final slotTop = rect.top * canvasHeight + gap;
      final slotWidth = rect.width * canvasWidth - gap * 2;
      final slotHeight = rect.height * canvasHeight - gap * 2;
      
      final slotRect = Rect.fromLTWH(slotLeft, slotTop, slotWidth, slotHeight);
      
      if (slotRect.contains(localPosition)) {
        targetIndex = i;
        break;
      }
    }

    setState(() {
      _dragHoverIndex = targetIndex;
      _dragOffset = event.position;
    });
  }

  void _handleLongPressEnd(int index) {
    if (_dragStartIndex != null && _dragHoverIndex != null && _dragStartIndex != _dragHoverIndex) {
      ref.read(collageProvider.notifier).swapImages(_dragStartIndex!, _dragHoverIndex!);
    }
    
    setState(() {
      _dragStartIndex = null;
      _dragHoverIndex = null;
      _dragOffset = null;
    });
  }

  Widget _buildTextLayerOverlay(
    BuildContext context,
    CollageState _,
    CollageTextLayer layer,
    double width,
    double height,
  ) {
    final text = layer.text.trim();
    final offset = layer.normalizedOffset;
    final scale = layer.scale;
    final fontFamily = layer.fontFamily;

    final centerX = offset.dx * width;
    final centerY = offset.dy * height;

    final textStyle = TextStyle(
      color: layer.color.withValues(alpha: layer.opacity.clamp(0.05, 1.0)),
      fontSize: layer.fontSize * scale,
      fontFamily: fontFamily == 'Roboto' ? null : fontFamily,
      fontWeight: layer.bold
          ? (fontFamily == 'Impact' || fontFamily == 'sans-serif'
              ? FontWeight.w900
              : FontWeight.bold)
          : FontWeight.w400,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      shadows: [
        Shadow(
          offset: const Offset(1, 1),
          blurRadius: 4,
          color: Colors.black.withValues(alpha: 0.8),
        ),
        Shadow(
          offset: const Offset(-1, -1),
          blurRadius: 4,
          color: Colors.black.withValues(alpha: 0.8),
        ),
      ],
    );

    final isActive = _activeTextLayerId == layer.id;

    return Positioned(
      left: centerX,
      top: centerY,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: layer.rotation,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 44),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _activeTextLayerId = layer.id;
                    });
                  },
                  onDoubleTap: () {
                    showCollageTextDialog(context, initialLayerId: layer.id);
                  },
                  onScaleStart: (details) {
                    _initialTextRotation = layer.rotation;
                    _initialTextScale = layer.scale;
                    setState(() {
                      _activeTextLayerId = layer.id;
                    });
                  },
                  onScaleUpdate: (details) {
                    final deltaDx = details.focalPointDelta.dx / width;
                    final deltaDy = details.focalPointDelta.dy / height;
                    final newDx = (layer.normalizedOffset.dx + deltaDx).clamp(0.02, 0.98);
                    final newDy = (layer.normalizedOffset.dy + deltaDy).clamp(0.02, 0.98);
                    ref.read(collageProvider.notifier).setTextLayerOffset(layer.id, Offset(newDx, newDy));

                    if (details.pointerCount > 1) {
                      final newScale = (_initialTextScale * details.scale).clamp(0.3, 5.0);
                      ref.read(collageProvider.notifier).setTextLayerScale(layer.id, newScale);

                      final rotationDelta = details.rotation;
                      final newRotation = _initialTextRotation + rotationDelta;
                      ref.read(collageProvider.notifier).setTextLayerRotation(layer.id, newRotation);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isActive
                            ? Colors.blueAccent
                            : Colors.transparent,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: isActive
                          ? Colors.blueAccent.withValues(alpha: 0.1)
                          : Colors.transparent,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width * 0.9),
                      child: Text(
                        text,
                        textAlign: layer.alignment,
                        style: textStyle,
                      ),
                    ),
                  ),
                ),
              ),
              if (isActive) ...[
                // Top 360° Rotation Handle with stalk
                Positioned(
                  top: 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) {
                            setState(() {
                              _activeTextLayerId = layer.id;
                            });
                          },
                          onPanUpdate: (details) {
                            final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                            if (canvasBox != null) {
                              final localTouch = canvasBox.globalToLocal(details.globalPosition);
                              final dx = localTouch.dx - centerX;
                              final dy = localTouch.dy - centerY;
                              final angle = math.atan2(dy, dx) + (math.pi / 2);
                              ref.read(collageProvider.notifier).setTextLayerRotation(layer.id, angle);
                            }
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.rotate_right_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 14,
                          color: Colors.blueAccent,
                        ),
                      ],
                    ),
                  ),
                ),
                // Corner Handles for drag-resize
                Positioned(
                  right: 4,
                  bottom: 32,
                  child: _buildCornerResizeHandle(layer, centerX, centerY),
                ),
                Positioned(
                  left: 4,
                  bottom: 32,
                  child: _buildCornerResizeHandle(layer, centerX, centerY),
                ),
                // Top-right edit handle
                Positioned(
                  right: 4,
                  top: 32,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      showCollageTextDialog(context, initialLayerId: layer.id);
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Top-left delete handle
                Positioned(
                  left: 4,
                  top: 32,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ref.read(collageProvider.notifier).removeTextLayer(layer.id);
                      setState(() {
                        _activeTextLayerId = null;
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCornerResizeHandle(CollageTextLayer layer, double centerX, double centerY) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        setState(() {
          _activeTextLayerId = layer.id;
        });
        final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
        if (canvasBox != null) {
          final localTouch = canvasBox.globalToLocal(details.globalPosition);
          _textResizeStartDist = (localTouch - Offset(centerX, centerY)).distance;
          _textResizeStartScale = layer.scale;
        }
      },
      onPanUpdate: (details) {
        final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
        if (canvasBox != null && _textResizeStartDist > 5.0) {
          final localTouch = canvasBox.globalToLocal(details.globalPosition);
          final currentDist = (localTouch - Offset(centerX, centerY)).distance;
          final factor = currentDist / _textResizeStartDist;
          final newScale = (_textResizeStartScale * factor).clamp(0.3, 5.0);
          ref.read(collageProvider.notifier).setTextLayerScale(layer.id, newScale);
        }
      },
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotOptionsSheet extends ConsumerWidget {
  final int slotIndex;

  const _SlotOptionsSheet({required this.slotIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collageProvider);
    if (slotIndex >= state.images.length || !state.images[slotIndex].hasImage) {
      return const SizedBox.shrink();
    }
    final slot = state.images[slotIndex];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            8 + (bottomInset > 0 ? 6 : 10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              // Header with Title, zoom badge, and Close Button
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Slot ${slotIndex + 1} Options',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(slot.scale * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 1: Zoom In, Zoom Out, Fit Mode (keeps menu open)
              Row(
                children: [
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.zoom_in_rounded,
                      label: 'Zoom In',
                      subtitle: '${(slot.scale * 100).toInt()}%',
                      onTap: () {
                        ref.read(collageProvider.notifier).setScale(
                              slotIndex,
                              (slot.scale + 0.2).clamp(1.0, 5.0),
                            );
                        if (slot.scale <= 1.0) {
                          ref
                              .read(collageProvider.notifier)
                              .setOffset(slotIndex, 0.0, 0.0);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.zoom_out_rounded,
                      label: 'Zoom Out',
                      subtitle: slot.scale > 1.0 ? '-20%' : '100%',
                      onTap: () {
                        final newScale = (slot.scale - 0.2).clamp(1.0, 5.0);
                        ref
                            .read(collageProvider.notifier)
                            .setScale(slotIndex, newScale);
                        if (newScale <= 1.0) {
                          ref
                              .read(collageProvider.notifier)
                              .setOffset(slotIndex, 0.0, 0.0);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.fit_screen_rounded,
                      label: 'Fit Mode',
                      subtitle: switch (slot.fitMode) {
                        ImageFitMode.cover => 'Cover',
                        ImageFitMode.contain => 'Contain',
                        ImageFitMode.fill => 'Fill',
                      },
                      onTap: () {
                        ref
                            .read(collageProvider.notifier)
                            .cycleFitMode(slotIndex);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: Rotate, Replace, Remove (keeps menu open except on Remove)
              Row(
                children: [
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.rotate_right_rounded,
                      label: 'Rotate',
                      subtitle: '+90°',
                      onTap: () {
                        ref
                            .read(collageProvider.notifier)
                            .rotateSlot(slotIndex);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.image_rounded,
                      label: 'Replace',
                      subtitle: 'Gallery',
                      onTap: () {
                        ref
                            .read(collageProvider.notifier)
                            .addImageToSlot(context, slotIndex);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                      subtitle: 'Clear slot',
                      color: Colors.redAccent,
                      onTap: () {
                        ref
                            .read(collageProvider.notifier)
                            .removeImageFromSlot(slotIndex);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _OptionButton({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = color ?? theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.22),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: primaryColor),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: primaryColor.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
