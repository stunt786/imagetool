import 'package:flutter/material.dart';

import '../models/image_to_pdf_state.dart';

class PdfSettingsPanel extends StatefulWidget {
  const PdfSettingsPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final PdfPageSettings settings;
  final ValueChanged<PdfPageSettings> onSettingsChanged;

  @override
  State<PdfSettingsPanel> createState() => _PdfSettingsPanelState();
}

class _PdfSettingsPanelState extends State<PdfSettingsPanel> {
  late final Map<String, TextEditingController> _controllers = {
    'Top': TextEditingController(
        text: widget.settings.marginTop.toStringAsFixed(2)),
    'Bottom': TextEditingController(
        text: widget.settings.marginBottom.toStringAsFixed(2)),
    'Left': TextEditingController(
        text: widget.settings.marginLeft.toStringAsFixed(2)),
    'Right': TextEditingController(
        text: widget.settings.marginRight.toStringAsFixed(2)),
  };
  late final Map<String, FocusNode> _focusNodes = {
    'Top': FocusNode(),
    'Bottom': FocusNode(),
    'Left': FocusNode(),
    'Right': FocusNode(),
  };

  @override
  void didUpdateWidget(covariant PdfSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final values = <String, double>{
      'Top': widget.settings.marginTop,
      'Bottom': widget.settings.marginBottom,
      'Left': widget.settings.marginLeft,
      'Right': widget.settings.marginRight,
    };
    for (final entry in values.entries) {
      final controller = _controllers[entry.key]!;
      if (!_focusNodes[entry.key]!.hasFocus &&
          controller.text != entry.value.toStringAsFixed(2)) {
        controller.text = entry.value.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PDF Settings',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingRow(
            context,
            label: 'Page Size',
            child: _buildDropdown<PdfPageSize>(
              value: widget.settings.pageSize,
              items: const [
                (PdfPageSize.a4, 'A4'),
                (PdfPageSize.a3, 'A3'),
                (PdfPageSize.usLetter, 'US Letter'),
                (PdfPageSize.usLegal, 'US Legal'),
                (PdfPageSize.matchImage, 'Match Image'),
              ],
              onChanged: (value) {
                if (value != null) {
                  widget.onSettingsChanged(
                      widget.settings.copyWith(pageSize: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Orientation',
            child: _buildDropdown<PdfOrientation>(
              value: widget.settings.orientation,
              items: const [
                (PdfOrientation.portrait, 'Portrait'),
                (PdfOrientation.landscape, 'Landscape'),
                (PdfOrientation.auto, 'Auto'),
              ],
              onChanged: (value) {
                if (value != null) {
                  widget.onSettingsChanged(
                      widget.settings.copyWith(orientation: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Fit Mode',
            child: _buildDropdown<ImageFitMode>(
              value: widget.settings.fitMode,
              items: const [
                (ImageFitMode.fit, 'Fit'),
                (ImageFitMode.fill, 'Fill'),
                (ImageFitMode.center, 'Center'),
                (ImageFitMode.stretch, 'Stretch'),
              ],
              onChanged: (value) {
                if (value != null) {
                  widget.onSettingsChanged(
                      widget.settings.copyWith(fitMode: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Quality',
            child: _buildDropdown<PdfQuality>(
              value: widget.settings.quality,
              items: const [
                (PdfQuality.optimized, 'Optimized'),
                (PdfQuality.highQuality, 'High Quality'),
              ],
              onChanged: (value) {
                if (value != null) {
                  widget.onSettingsChanged(
                      widget.settings.copyWith(quality: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Margins (inches)',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildMarginField(
                      context,
                      'Top',
                      widget.settings.marginTop,
                      (v) => widget.onSettingsChanged(
                          widget.settings.copyWith(marginTop: v)))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildMarginField(
                      context,
                      'Bottom',
                      widget.settings.marginBottom,
                      (v) => widget.onSettingsChanged(
                          widget.settings.copyWith(marginBottom: v)))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildMarginField(
                      context,
                      'Left',
                      widget.settings.marginLeft,
                      (v) => widget.onSettingsChanged(
                          widget.settings.copyWith(marginLeft: v)))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildMarginField(
                      context,
                      'Right',
                      widget.settings.marginRight,
                      (v) => widget.onSettingsChanged(
                          widget.settings.copyWith(marginRight: v)))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(BuildContext context,
      {required String label, required Widget child}) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildMarginField(BuildContext context, String label, double value,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            suffixText: 'in',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          controller: _controllers[label]!,
          focusNode: _focusNodes[label],
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed != null && parsed >= 0 && parsed <= 10) {
              onChanged(parsed);
            }
          },
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(12),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item.$1,
          child: Text(item.$2),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
