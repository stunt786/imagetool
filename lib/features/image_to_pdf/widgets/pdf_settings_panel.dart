import 'package:flutter/material.dart';

import '../models/image_to_pdf_state.dart';

class PdfSettingsPanel extends StatelessWidget {
  const PdfSettingsPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final PdfPageSettings settings;
  final ValueChanged<PdfPageSettings> onSettingsChanged;

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
              value: settings.pageSize,
              items: const [
                (PdfPageSize.a4, 'A4'),
                (PdfPageSize.a3, 'A3'),
                (PdfPageSize.usLetter, 'US Letter'),
                (PdfPageSize.usLegal, 'US Legal'),
                (PdfPageSize.matchImage, 'Match Image'),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSettingsChanged(settings.copyWith(pageSize: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Orientation',
            child: _buildDropdown<PdfOrientation>(
              value: settings.orientation,
              items: const [
                (PdfOrientation.portrait, 'Portrait'),
                (PdfOrientation.landscape, 'Landscape'),
                (PdfOrientation.auto, 'Auto'),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSettingsChanged(settings.copyWith(orientation: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Fit Mode',
            child: _buildDropdown<ImageFitMode>(
              value: settings.fitMode,
              items: const [
                (ImageFitMode.fit, 'Fit'),
                (ImageFitMode.fill, 'Fill'),
                (ImageFitMode.center, 'Center'),
                (ImageFitMode.stretch, 'Stretch'),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSettingsChanged(settings.copyWith(fitMode: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Quality',
            child: _buildDropdown<PdfQuality>(
              value: settings.quality,
              items: const [
                (PdfQuality.optimized, 'Optimized'),
                (PdfQuality.highQuality, 'High Quality'),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSettingsChanged(settings.copyWith(quality: value));
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingRow(
            context,
            label: 'Margin (mm)',
            child: SizedBox(
              width: 80,
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                controller: TextEditingController(text: settings.marginMm.toStringAsFixed(1)),
                onChanged: (value) {
                  final margin = double.tryParse(value);
                  if (margin != null && margin >= 0 && margin <= 50) {
                    onSettingsChanged(settings.copyWith(marginMm: margin));
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(BuildContext context, {required String label, required Widget child}) {
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
