import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/utils/image_saver.dart';
import '../notifiers/collage_notifier.dart';

class CollageToolbar extends ConsumerWidget {
  const CollageToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collageProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit controls row
                Row(
                  children: [
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.grid_on,
                        label: 'Gap',
                        onTap: () => _showGapSlider(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.rounded_corner,
                        label: 'Radius',
                        onTap: () => _showRadiusSlider(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.palette,
                        label: 'Color',
                        onTap: () => _showColorPicker(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.title,
                        label: 'Text',
                        onTap: () => _showTextCaptionSheet(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.add_photo_alternate,
                        label: 'Add',
                        onTap: state.imageCount >= 6
                            ? null
                            : () {
                                ref
                                    .read(collageProvider.notifier)
                                    .pickImages(context);
                                InterstitialTracker.instance.trackAction();
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Action row
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
                        label: Text(state.isExporting ? 'Saving...' : 'Save'),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                const SizedBox(height: 8),
              ],
            );
          },
        ),
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
                    ref
                        .read(collageProvider.notifier)
                        .setBackgroundColor(color);
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

  void _showTextCaptionSheet(BuildContext context, WidgetRef ref) {
    final colorOptions = [
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    final fontStyles = [
      ('Roboto', 'Default (Roboto)'),
      ('serif', 'Serif'),
      ('monospace', 'Monospace'),
      ('cursive', 'Cursive'),
      ('Impact', 'Bold Sans'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final currentState = ref.watch(collageProvider);
          final layers = currentState.textLayers;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Text Layers',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          ref.read(collageProvider.notifier).addTextLayer();
                        },
                      ),
                    ],
                  ),
                  if (layers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No text layers. Tap + to add one.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        itemCount: layers.length,
                        itemBuilder: (context, index) {
                          final layer = layers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          decoration: const InputDecoration(
                                            hintText: 'Enter text...',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                          ),
                                          controller: TextEditingController(
                                            text: layer.text,
                                          ),
                                          onChanged: (val) {
                                            ref
                                                .read(collageProvider.notifier)
                                                .updateTextLayer(layer.id, text: val);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () {
                                          ref
                                              .read(collageProvider.notifier)
                                              .removeTextLayer(layer.id);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        ...colorOptions.map((c) {
                                          final isSelected = c == layer.color;
                                          return GestureDetector(
                                            onTap: () {
                                              ref
                                                  .read(collageProvider.notifier)
                                                  .updateTextLayer(layer.id, color: c);
                                              setState(() {});
                                            },
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: c,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Theme.of(context).colorScheme.primary
                                                      : Colors.grey.shade400,
                                                  width: isSelected ? 2 : 1,
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                        const SizedBox(width: 8),
                                        ...fontStyles.map((item) {
                                          final isSelected = layer.fontFamily == item.$1;
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: ChoiceChip(
                                              label: Text(
                                                item.$2,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontFamily:
                                                      item.$1 == 'Roboto' ? null : item.$1,
                                                  fontWeight: item.$1 == 'Impact'
                                                      ? FontWeight.w900
                                                      : null,
                                                ),
                                              ),
                                              selected: isSelected,
                                              onSelected: (_) {
                                                ref
                                                    .read(collageProvider.notifier)
                                                    .updateTextLayer(
                                                      layer.id,
                                                      fontFamily: item.$1,
                                                    );
                                                setState(() {});
                                              },
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.text_fields, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Slider(
                                          value: layer.fontSize,
                                          min: 12,
                                          max: 48,
                                          divisions: 36,
                                          label: '${layer.fontSize.toInt()}px',
                                          onChanged: (val) {
                                            ref
                                                .read(collageProvider.notifier)
                                                .updateTextLayer(layer.id, fontSize: val);
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 40,
                                        child: Text(
                                          '${layer.fontSize.toInt()}',
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.rotate_right, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Slider(
                                          value: layer.rotation,
                                          min: -math.pi,
                                          max: math.pi,
                                          divisions: 60,
                                          label: '${(layer.rotation * 180 / math.pi).toInt()}°',
                                          onChanged: (val) {
                                            ref
                                                .read(collageProvider.notifier)
                                                .setTextLayerRotation(layer.id, val);
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 40,
                                        child: Text(
                                          '${(layer.rotation * 180 / math.pi).toInt()}°',
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportCollage(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(collageProvider.notifier).exportCollage();
      if (bytes == null) return;

      final fileName = 'collage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final saveResult = await saveImageBytes(bytes, fileName: fileName);

      if (context.mounted) {
        ref.read(editHistoryProvider.notifier).addEntry(
              EditHistoryItem(
                fileName: saveResult.fileName,
                toolUsed: 'Collage Builder',
                editedAt: DateTime.now(),
                toolIcon: Icons.dashboard_customize_rounded,
                thumbnailPath: saveResult.path,
              ),
            );
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
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDisabled
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDisabled
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
