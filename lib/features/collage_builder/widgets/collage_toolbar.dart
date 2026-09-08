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
                                ref.read(collageProvider.notifier).pickImages(context);
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

  void _showTextCaptionSheet(BuildContext context, WidgetRef ref) {
    final state = ref.read(collageProvider);
    final textController = TextEditingController(text: state.captionText ?? '');
    double size = state.captionSize;
    Color color = state.captionColor;
    Alignment alignment = state.captionAlignment;

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

    final alignments = [
      (Alignment.topLeft, 'Top Left', const Offset(0.15, 0.15)),
      (Alignment.topCenter, 'Top', const Offset(0.5, 0.15)),
      (Alignment.topRight, 'Top Right', const Offset(0.85, 0.15)),
      (Alignment.centerLeft, 'Left', const Offset(0.15, 0.5)),
      (Alignment.center, 'Center', const Offset(0.5, 0.5)),
      (Alignment.centerRight, 'Right', const Offset(0.85, 0.5)),
      (Alignment.bottomLeft, 'Bottom Left', const Offset(0.15, 0.85)),
      (Alignment.bottomCenter, 'Bottom', const Offset(0.5, 0.85)),
      (Alignment.bottomRight, 'Bottom Right', const Offset(0.85, 0.85)),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final currentState = ref.watch(collageProvider);
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
                        'Collage Caption',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (textController.text.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            textController.clear();
                            ref.read(collageProvider.notifier).setCaptionText('');
                            setState(() {});
                          },
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: 'Caption Text',
                      hintText: 'Enter overlay caption...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      ref.read(collageProvider.notifier).setCaptionText(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Font Style',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: fontStyles.map((item) {
                        final isSelected = currentState.captionFontFamily == item.$1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(
                              item.$2,
                              style: TextStyle(
                                fontFamily: item.$1 == 'Roboto' ? null : item.$1,
                                fontWeight: item.$1 == 'Impact' ? FontWeight.w900 : null,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() {});
                              ref.read(collageProvider.notifier).setCaptionFontFamily(item.$1);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Font Size: ${size.toInt()}px',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Slider(
                    value: size,
                    min: 12,
                    max: 48,
                    divisions: 36,
                    onChanged: (val) {
                      setState(() => size = val);
                      ref.read(collageProvider.notifier).setCaptionSize(val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Text Color',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colorOptions.map((c) {
                      final isSelected = c == color;
                      return GestureDetector(
                        onTap: () {
                          setState(() => color = c);
                          ref.read(collageProvider.notifier).setCaptionColor(c);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade400,
                              width: isSelected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Position Presets',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: alignments.map((item) {
                      final isSelected = item.$1 == alignment;
                      return ChoiceChip(
                        label: Text(item.$2),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => alignment = item.$1);
                          ref.read(collageProvider.notifier).setCaptionAlignment(item.$1);
                          ref.read(collageProvider.notifier).setCaptionNormalizedOffset(item.$3);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref
                                .read(collageProvider.notifier)
                                .setCaptionNormalizedOffset(const Offset(0.5, 0.85));
                            ref.read(collageProvider.notifier).setCaptionScale(1.0);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Caption position and scale reset'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Reset Position & Scale'),
                        ),
                      ),
                    ],
                  ),
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
              color: isDisabled ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDisabled ? scheme.onSurfaceVariant.withValues(alpha: 0.4) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
