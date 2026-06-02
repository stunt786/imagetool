import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notifiers/document_batch_notifier.dart';

class DocumentReviewScreen extends ConsumerWidget {
  const DocumentReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(documentBatchProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!batch.hasPages) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scanned Pages')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 64, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text('No pages scanned',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${batch.pageCount} Page${batch.pageCount == 1 ? '' : 's'}'),
        actions: [
          TextButton.icon(
            onPressed: () {
              ref.read(documentBatchProvider.notifier).clearBatch();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: batch.pages.length,
        onReorder: (oldIndex, newIndex) {
          ref.read(documentBatchProvider.notifier).reorderPages(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final page = batch.pages[index];
          return _PageTile(
            key: ValueKey('${page.path}_$index'),
            index: index,
            page: page,
            onTap: () => context.push('/camera/filter', extra: index),
            onRemove: () {
              ref.read(documentBatchProvider.notifier).removePage(index);
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/camera/filter', extra: -1),
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Apply Filter to All'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    context.push('/images/to-pdf');
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Create PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.page,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final dynamic page;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Page number
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: page.imageBytes != null
                      ? Image.memory(
                          page.displayBytes,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _placeholderIcon(scheme),
                        )
                      : _placeholderIcon(scheme),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.name ?? 'Page ${index + 1}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (page.filterType != null &&
                          page.filterType.name != 'none')
                        Chip(
                          label: Text(
                            page.filterType.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.primary,
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  onPressed: onTap,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.close, size: 20, color: scheme.error),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon(ColorScheme scheme) {
    return Container(
      width: 48,
      height: 64,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }
}
