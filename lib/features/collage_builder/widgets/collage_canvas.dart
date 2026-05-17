import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' as vec;

import '../models/collage_state.dart';
import '../notifiers/collage_notifier.dart';

class CollageCanvas extends ConsumerStatefulWidget {
  const CollageCanvas({super.key});

  @override
  ConsumerState<CollageCanvas> createState() => _CollageCanvasState();
}

class _CollageCanvasState extends ConsumerState<CollageCanvas> {
  int? _dragStartIndex;
  int? _dragHoverIndex;
  double _currentScale = 1.0;
  double _initialScale = 1.0;
  int? _pinchSlotIndex;

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

        return Center(
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
                children: List.generate(state.layout.slotCount, (index) {
                  return _buildSlot(context, state, index, width, height);
                }),
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
    final isDragTarget = _dragHoverIndex == index && _dragStartIndex != index;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () => _handleSlotTap(context, index),
        onScaleStart: (details) => _handleScaleStart(index, details),
        onScaleUpdate: (details) => _handleScaleUpdate(index, details),
        onScaleEnd: (details) => _handleScaleEnd(index),
        onLongPressStart: (details) => _handleLongPressStart(index, details),
        onLongPressMoveUpdate: (details) => _handleLongPressMove(index, details, canvasWidth, canvasHeight),
        onLongPressEnd: (details) => _handleLongPressEnd(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: slot.hasImage 
                ? (isDragTarget ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent)
                : const Color(0xFFD6E4FF),
            border: Border.all(
              color: isDragTarget 
                  ? Colors.blue
                  : slot.hasImage 
                      ? Colors.transparent 
                      : const Color(0xFF5B4DFF).withValues(alpha: 0.3),
              width: isDragTarget ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(state.cornerRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(state.cornerRadius),
            child: slot.hasImage
                ? _buildImageContent(slot, width, height, index)
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
    );
  }

  Widget _buildImageContent(CollageImageSlot slot, double width, double height, int index) {
    final isPinching = _pinchSlotIndex == index;
    final scale = isPinching ? _currentScale : slot.scale;
    final offsetX = isPinching ? _currentScale : slot.offsetX;
    final offsetY = isPinching ? _currentScale : slot.offsetY;

    return Stack(
      children: [
        Positioned.fill(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByVector3(vec.Vector3(offsetX * width * 0.1, offsetY * height * 0.1, 0))
              ..scaleByDouble(scale, scale, scale, 1.0),
            alignment: Alignment.center,
            child: Image.memory(
              slot.imageBytes!,
              fit: slot.fitMode == ImageFitMode.cover
                  ? BoxFit.cover
                  : slot.fitMode == ImageFitMode.contain
                      ? BoxFit.contain
                      : BoxFit.fill,
              gaplessPlayback: true,
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

  void _handleSlotTap(BuildContext context, int index) {
    final state = ref.read(collageProvider);
    if (state.images[index].hasImage) {
      _showSlotOptions(context, index);
    } else {
      ref.read(collageProvider.notifier).addImageToSlot(index);
    }
  }

  void _showSlotOptions(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _SlotOptionsSheet(slotIndex: index),
    );
  }

  void _handleScaleStart(int index, ScaleStartDetails details) {
    if (details.pointerCount == 2) {
      final state = ref.read(collageProvider);
      if (state.images[index].hasImage) {
        _pinchSlotIndex = index;
        _initialScale = state.images[index].scale;
        _currentScale = _initialScale;
      }
    }
  }

  void _handleScaleUpdate(int index, ScaleUpdateDetails details) {
    if (_pinchSlotIndex == index && details.pointerCount == 2) {
      final state = ref.read(collageProvider);
      if (state.images[index].hasImage) {
        _currentScale = (_initialScale * details.scale).clamp(1.0, 5.0);
        ref.read(collageProvider.notifier).setScale(index, _currentScale);
      }
    }
  }

  void _handleScaleEnd(int index) {
    if (_pinchSlotIndex == index) {
      _pinchSlotIndex = null;
      _currentScale = 1.0;
      _initialScale = 1.0;
    }
  }

  void _handleLongPressStart(int index, LongPressStartDetails details) {
    final state = ref.read(collageProvider);
    if (state.images[index].hasImage) {
      setState(() {
        _dragStartIndex = index;
      });
    }
  }

  void _handleLongPressMove(int index, LongPressMoveUpdateDetails details, double canvasWidth, double canvasHeight) {
    if (_dragStartIndex == null) return;

    final state = ref.read(collageProvider);
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localPosition = details.localPosition;
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
    });
  }

  void _handleLongPressEnd(int index) {
    if (_dragStartIndex != null && _dragHoverIndex != null && _dragStartIndex != _dragHoverIndex) {
      ref.read(collageProvider.notifier).swapImages(_dragStartIndex!, _dragHoverIndex!);
    }
    
    setState(() {
      _dragStartIndex = null;
      _dragHoverIndex = null;
    });
  }
}

class _SlotOptionsSheet extends ConsumerWidget {
  final int slotIndex;

  const _SlotOptionsSheet({required this.slotIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collageProvider);
    final slot = state.images[slotIndex];

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Slot ${slotIndex + 1} Options',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionButton(
                icon: Icons.zoom_in,
                label: 'Zoom In',
                onTap: () {
                  ref.read(collageProvider.notifier).setScale(
                        slotIndex,
                        (slot.scale + 0.2).clamp(1.0, 5.0),
                      );
                  Navigator.pop(context);
                },
              ),
              _OptionButton(
                icon: Icons.zoom_out,
                label: 'Zoom Out',
                onTap: () {
                  ref.read(collageProvider.notifier).setScale(
                        slotIndex,
                        (slot.scale - 0.2).clamp(1.0, 5.0),
                      );
                  Navigator.pop(context);
                },
              ),
              _OptionButton(
                icon: Icons.fit_screen,
                label: 'Fit Mode',
                onTap: () {
                  ref.read(collageProvider.notifier).cycleFitMode(slotIndex);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OptionButton(
                icon: Icons.image,
                label: 'Replace',
                onTap: () {
                  Navigator.pop(context);
                  ref.read(collageProvider.notifier).addImageToSlot(slotIndex);
                },
              ),
              _OptionButton(
                icon: Icons.delete,
                label: 'Remove',
                color: Colors.red,
                onTap: () {
                  ref.read(collageProvider.notifier).removeImageFromSlot(slotIndex);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
