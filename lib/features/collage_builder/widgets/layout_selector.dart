import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collage_state.dart';
import '../notifiers/collage_notifier.dart';

class LayoutSelector extends ConsumerWidget {
  const LayoutSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collageProvider);

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Layouts',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          ClipRect(
            child: SizedBox(
              height: 78,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: CollageLayout.all.length,
                itemBuilder: (context, index) {
                  final layout = CollageLayout.all[index];
                  final isSelected = state.layout.id == layout.id;

                  return _LayoutOption(
                    layout: layout,
                    isSelected: isSelected,
                    onTap: () {
                      ref.read(collageProvider.notifier).changeLayout(layout);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutOption extends StatelessWidget {
  final CollageLayout layout;
  final bool isSelected;
  final VoidCallback onTap;

  const _LayoutOption({
    required this.layout,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LayoutPreview(layout: layout),
              const SizedBox(height: 4),
              Text(
                '${layout.slotCount}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutPreview extends StatelessWidget {
  final CollageLayout layout;

  const _LayoutPreview({required this.layout});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _LayoutPreviewPainter(layout: layout),
      ),
    );
  }
}

class _LayoutPreviewPainter extends CustomPainter {
  final CollageLayout layout;

  _LayoutPreviewPainter({required this.layout});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final rect in layout.slotRects) {
      final r = Rect.fromLTWH(
        rect.left * size.width,
        rect.top * size.height,
        rect.width * size.width,
        rect.height * size.height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
