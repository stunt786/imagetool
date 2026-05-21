import 'package:flutter/material.dart';

import '../models/pdf_convert_state.dart';

class ConvertSettingsPanel extends StatelessWidget {
  const ConvertSettingsPanel({
    super.key,
    required this.state,
    required this.onFormatChanged,
    required this.onDpiChanged,
  });

  final PdfConvertState state;
  final ValueChanged<ConvertFormat> onFormatChanged;
  final ValueChanged<ConvertDpi> onDpiChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImageFormat =
        state.outputFormat == ConvertFormat.jpg ||
        state.outputFormat == ConvertFormat.png;

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
            'Output Format',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Format selector
          ...ConvertFormat.values.map((format) {
            final isSelected = format == state.outputFormat;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onFormatChanged(format),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Radio<ConvertFormat>(
                          value: format,
                          // ignore: deprecated_member_use
                          onChanged: (_) => onFormatChanged(format),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                format.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                format.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // DPI selector (only for image formats)
          if (isImageFormat) ...[
            const SizedBox(height: 16),
            Text(
              'Resolution (DPI)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...ConvertDpi.values.map((dpi) {
              final isSelected = dpi == state.dpi;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => onDpiChanged(dpi),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<ConvertDpi>(
                            value: dpi,
                            // ignore: deprecated_member_use
                            onChanged: (_) => onDpiChanged(dpi),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dpi.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          // DOCX limitation note
          if (state.outputFormat == ConvertFormat.docx) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DOCX conversion extracts text and creates a basic Word document. Complex layouts, images, and formatting may not be preserved.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
