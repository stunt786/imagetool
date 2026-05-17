import 'dart:typed_data';

import 'package:flutter/material.dart';

class ImageThumbnailCard extends StatelessWidget {
  const ImageThumbnailCard({
    super.key,
    required this.index,
    required this.imageBytes,
    required this.imageName,
    required this.imageSize,
    this.onRemove,
    this.onDragStart,
    this.onDragEnd,
    this.isDragging = false,
  });

  final int index;
  final Uint8List imageBytes;
  final String imageName;
  final int imageSize;
  final VoidCallback? onRemove;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      elevation: isDragging ? 4 : 1,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDragging 
                ? theme.colorScheme.primary 
                : theme.colorScheme.outlineVariant,
            width: isDragging ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.broken_image,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (onRemove != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: onRemove,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    imageName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(imageSize / 1024).toStringAsFixed(1)} KB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
