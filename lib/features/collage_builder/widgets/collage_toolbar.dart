import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/utils/image_saver.dart';
import '../notifiers/collage_notifier.dart';

class CollageToolbar extends ConsumerWidget {
  const CollageToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collageProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ToolbarButton(
                icon: Icons.grid_on,
                label: 'Gap',
                onTap: () => _showGapSlider(context, ref),
              ),
              const SizedBox(width: 12),
              _ToolbarButton(
                icon: Icons.rounded_corner,
                label: 'Radius',
                onTap: () => _showRadiusSlider(context, ref),
              ),
              const SizedBox(width: 12),
              _ToolbarButton(
                icon: Icons.palette,
                label: 'Color',
                onTap: () => _showColorPicker(context, ref),
              ),
              const Spacer(),
              _ToolbarButton(
                icon: Icons.add_photo_alternate,
                label: 'Add',
                onTap: () {
                  ref.read(collageProvider.notifier).pickImages(context);
                  InterstitialTracker.instance.trackAction();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isExporting
                      ? null
                      : () => _exportCollage(context, ref),
                  icon: state.isExporting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: state.exportProgress,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(state.isExporting ? 'Exporting...' : 'Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.imageCount == 0
                      ? null
                      : () => _shareCollage(context, ref),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showGapSlider(BuildContext context, WidgetRef ref) {
    final state = ref.read(collageProvider);
    double gap = state.gap;

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gap: ${gap.toInt()}px',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: gap,
                min: 0,
                max: 20,
                divisions: 20,
                onChanged: (value) {
                  setState(() => gap = value);
                  ref.read(collageProvider.notifier).setGap(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRadiusSlider(BuildContext context, WidgetRef ref) {
    final state = ref.read(collageProvider);
    double radius = state.cornerRadius;

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Corner Radius: ${radius.toInt()}px',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: radius,
                min: 0,
                max: 50,
                divisions: 50,
                onChanged: (value) {
                  setState(() => radius = value);
                  ref.read(collageProvider.notifier).setCornerRadius(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final colors = [
      const Color(0xFFE8EAF6),
      Colors.white,
      Colors.black,
      const Color(0xFFFFF3E0),
      const Color(0xFFE8F5E9),
      const Color(0xFFE3F2FD),
      const Color(0xFFFCE4EC),
      const Color(0xFFF3E5F5),
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Background Color',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((color) {
                return GestureDetector(
                  onTap: () {
                    ref.read(collageProvider.notifier).setBackgroundColor(color);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCollage(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(collageProvider.notifier).exportCollage();
      if (bytes == null) return;

      final fileName = 'collage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await saveImageBytes(bytes, fileName: fileName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved'),
            duration: Duration(seconds: 2),
          ),
        );
        InterstitialTracker.instance.trackAction();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _shareCollage(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(collageProvider.notifier).exportCollage();
      if (bytes == null) return;

      final fileName = 'collage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await saveImageBytes(bytes, fileName: fileName);

      if (result.path == null) return;

      await Share.shareXFiles(
        [XFile(result.path!)],
        subject: 'Check out this collage from PixelTools',
        text: 'Collage created with PixelTools',
      );
      InterstitialTracker.instance.trackAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
