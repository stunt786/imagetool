import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collage_state.dart';
import '../notifiers/collage_notifier.dart';

/// Shows the dedicated Text Management popup dialog for the collage builder.
Future<void> showCollageTextDialog(
  BuildContext context, {
  String? initialLayerId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => CollageTextDialog(initialLayerId: initialLayerId),
  );
}

class CollageTextDialog extends ConsumerStatefulWidget {
  final String? initialLayerId;

  const CollageTextDialog({super.key, this.initialLayerId});

  @override
  ConsumerState<CollageTextDialog> createState() => _CollageTextDialogState();
}

class _CollageTextDialogState extends ConsumerState<CollageTextDialog> {
  late TextEditingController _textController;
  String? _selectedLayerId;

  static const List<Color> _presetColors = [
    Colors.white,
    Colors.black,
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFFE8EAF6),
    Color(0xFFFF7043),
    Color(0xFF00897B),
  ];

  static const List<(String, String)> _fontStyles = [
    ('Roboto', 'Default'),
    ('serif', 'Serif'),
    ('monospace', 'Mono'),
    ('cursive', 'Cursive'),
    ('Impact', 'Impact'),
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(collageProvider);
      if (state.textLayers.isEmpty) {
        ref.read(collageProvider.notifier).addTextLayer();
        final newLayers = ref.read(collageProvider).textLayers;
        if (newLayers.isNotEmpty) {
          _selectLayer(newLayers.last.id);
        }
      } else {
        final targetId = widget.initialLayerId ?? state.textLayers.first.id;
        _selectLayer(targetId);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _selectLayer(String id) {
    final state = ref.read(collageProvider);
    final layer = state.textLayers.where((l) => l.id == id).firstOrNull;
    setState(() {
      _selectedLayerId = id;
      _textController.text = layer?.text ?? '';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collageProvider);
    final layers = state.textLayers;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Resolve current selected layer
    CollageTextLayer? currentLayer;
    if (_selectedLayerId != null) {
      currentLayer = layers.where((l) => l.id == _selectedLayerId).firstOrNull;
    }
    if (currentLayer == null && layers.isNotEmpty) {
      currentLayer = layers.first;
      _selectedLayerId = currentLayer.id;
      _textController.text = currentLayer.text;
    }

    final dialogHeight = MediaQuery.sizeOf(context).height * 0.82;
    final dialogWidth = math.min(MediaQuery.sizeOf(context).width * 0.94, 480.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: scheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.title_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Manage Text',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Layer Selector Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int i = 0; i < layers.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: layers[i].id == currentLayer?.id,
                                label: Text(
                                  layers[i].text.trim().isNotEmpty
                                      ? (layers[i].text.trim().length > 10
                                          ? '${layers[i].text.trim().substring(0, 10)}...'
                                          : layers[i].text.trim())
                                      : 'Text ${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: layers[i].id == currentLayer?.id
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                onSelected: (_) => _selectLayer(layers[i].id),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      ref.read(collageProvider.notifier).addTextLayer();
                      final updated = ref.read(collageProvider).textLayers;
                      if (updated.isNotEmpty) {
                        _selectLayer(updated.last.id);
                      }
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: currentLayer == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.text_fields_rounded, size: 48, color: scheme.outline),
                          const SizedBox(height: 12),
                          Text('No text layers', style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () {
                              ref.read(collageProvider.notifier).addTextLayer();
                              final updated = ref.read(collageProvider).textLayers;
                              if (updated.isNotEmpty) {
                                _selectLayer(updated.last.id);
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Text Layer'),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      children: [
                        // Live Preview Card
                        _buildLivePreview(currentLayer, state.backgroundColor, scheme),
                        const SizedBox(height: 16),

                        // Text input field
                        Text(
                          'Text Content',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: 'Enter text here...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: _textController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _textController.clear();
                                      ref
                                          .read(collageProvider.notifier)
                                          .updateTextLayer(currentLayer!.id, text: '');
                                      setState(() {});
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          maxLines: 2,
                          onChanged: (val) {
                            ref
                                .read(collageProvider.notifier)
                                .updateTextLayer(currentLayer!.id, text: val);
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 16),

                        // Typography & Font section
                        Text(
                          'Font Family',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _fontStyles.map((item) {
                              final isSelected = currentLayer!.fontFamily == item.$1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    item.$2,
                                    style: TextStyle(
                                      fontFamily: item.$1 == 'Roboto' ? null : item.$1,
                                      fontWeight:
                                          item.$1 == 'Impact' ? FontWeight.w900 : null,
                                      fontSize: 12,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    ref
                                        .read(collageProvider.notifier)
                                        .updateTextLayer(currentLayer!.id, fontFamily: item.$1);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Formatting & Alignment Controls
                        Row(
                          children: [
                            // Alignment
                            Expanded(
                              flex: 3,
                              child: SegmentedButton<TextAlign>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: TextAlign.left,
                                    icon: Icon(Icons.format_align_left, size: 18),
                                  ),
                                  ButtonSegment(
                                    value: TextAlign.center,
                                    icon: Icon(Icons.format_align_center, size: 18),
                                  ),
                                  ButtonSegment(
                                    value: TextAlign.right,
                                    icon: Icon(Icons.format_align_right, size: 18),
                                  ),
                                ],
                                selected: {currentLayer.alignment},
                                onSelectionChanged: (val) {
                                  ref
                                      .read(collageProvider.notifier)
                                      .updateTextLayer(currentLayer!.id, alignment: val.first);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Bold / Italic
                            IconButton.filledTonal(
                              isSelected: currentLayer.bold,
                              icon: const Icon(Icons.format_bold, size: 20),
                              tooltip: 'Bold',
                              onPressed: () {
                                ref.read(collageProvider.notifier).updateTextLayer(
                                      currentLayer!.id,
                                      bold: !currentLayer.bold,
                                    );
                              },
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              isSelected: currentLayer.italic,
                              icon: const Icon(Icons.format_italic, size: 20),
                              tooltip: 'Italic',
                              onPressed: () {
                                ref.read(collageProvider.notifier).updateTextLayer(
                                      currentLayer!.id,
                                      italic: !currentLayer.italic,
                                    );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Font Size Slider
                        Row(
                          children: [
                            const Icon(Icons.format_size, size: 20),
                            const SizedBox(width: 8),
                            Text('Size: ${currentLayer.fontSize.toInt()}px'),
                            Expanded(
                              child: Slider(
                                value: currentLayer.fontSize,
                                min: 10,
                                max: 64,
                                divisions: 54,
                                onChanged: (val) {
                                  ref
                                      .read(collageProvider.notifier)
                                      .updateTextLayer(currentLayer!.id, fontSize: val);
                                },
                              ),
                            ),
                          ],
                        ),

                        // Opacity Slider
                        Row(
                          children: [
                            const Icon(Icons.opacity, size: 20),
                            const SizedBox(width: 8),
                            Text('Opacity: ${(currentLayer.opacity * 100).round()}%'),
                            Expanded(
                              child: Slider(
                                value: currentLayer.opacity.clamp(0.05, 1.0),
                                min: 0.05,
                                max: 1.0,
                                divisions: 19,
                                onChanged: (val) {
                                  ref
                                      .read(collageProvider.notifier)
                                      .updateTextLayer(currentLayer!.id, opacity: val);
                                },
                              ),
                            ),
                          ],
                        ),

                        // Rotation Slider
                        Row(
                          children: [
                            const Icon(Icons.rotate_right, size: 20),
                            const SizedBox(width: 8),
                            Text('Angle: ${(currentLayer.rotation * 180 / math.pi).toInt()}°'),
                            Expanded(
                              child: Slider(
                                value: currentLayer.rotation,
                                min: -math.pi,
                                max: math.pi,
                                divisions: 72,
                                onChanged: (val) {
                                  ref
                                      .read(collageProvider.notifier)
                                      .setTextLayerRotation(currentLayer!.id, val);
                                },
                              ),
                            ),
                            if (currentLayer.rotation != 0.0)
                              IconButton(
                                icon: const Icon(Icons.restart_alt, size: 18),
                                tooltip: 'Reset Rotation',
                                onPressed: () {
                                  ref
                                      .read(collageProvider.notifier)
                                      .setTextLayerRotation(currentLayer!.id, 0.0);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Color Palette
                        Text(
                          'Text Color',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _presetColors.map((color) {
                            final isSelected = currentLayer!.color == color;
                            return GestureDetector(
                              onTap: () {
                                ref
                                    .read(collageProvider.notifier)
                                    .updateTextLayer(currentLayer!.id, color: color);
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? scheme.primary : Colors.grey.shade400,
                                    width: isSelected ? 3 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        size: 18,
                                        color: color.computeLuminance() > 0.5
                                            ? Colors.black
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(
                children: [
                  if (currentLayer != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: () {
                        ref.read(collageProvider.notifier).removeTextLayer(currentLayer!.id);
                        final remaining = ref.read(collageProvider).textLayers;
                        if (remaining.isNotEmpty) {
                          _selectLayer(remaining.first.id);
                        } else {
                          setState(() {
                            _selectedLayerId = null;
                            _textController.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreview(
    CollageTextLayer layer,
    Color canvasBg,
    ColorScheme scheme,
  ) {
    final displayText = layer.text.trim().isEmpty ? 'Preview Text' : layer.text;
    final textStyle = TextStyle(
      color: layer.color.withValues(alpha: layer.opacity.clamp(0.05, 1.0)),
      fontSize: (layer.fontSize * 0.9).clamp(12.0, 36.0),
      fontFamily: layer.fontFamily == 'Roboto' ? null : layer.fontFamily,
      fontWeight: layer.bold
          ? (layer.fontFamily == 'Impact' ? FontWeight.w900 : FontWeight.bold)
          : FontWeight.w400,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      shadows: const [
        Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
        Shadow(offset: Offset(-1, -1), blurRadius: 3, color: Colors.black54),
      ],
    );

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: canvasBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Transform.rotate(
          angle: layer.rotation,
          child: Text(
            displayText,
            textAlign: layer.alignment,
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
