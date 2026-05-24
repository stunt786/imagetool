import 'package:flutter/material.dart';

import '../../../core/services/pdf_service.dart';
import '../models/pdf_merge_state.dart';

class PdfFileListTile extends StatelessWidget {
  const PdfFileListTile({
    super.key,
    required this.item,
    required this.index,
    required this.onRemove,
    required this.onReorderStart,
  });

  final MergePdfItem item;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onReorderStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Icon(
                Icons.drag_handle,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
          // Index badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // PDF icon
          Icon(
            Icons.picture_as_pdf,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.pageCount != null) '${item.pageCount} pages',
                    PdfService.formatFileSize(item.sizeBytes),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Remove button
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              Icons.close,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
