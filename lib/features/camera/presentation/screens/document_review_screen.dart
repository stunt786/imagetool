import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/utils/image_saver.dart';
import '../../models/scanned_page.dart';
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
        appBar: AppBar(title: const Text('Scan Preview')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 64,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
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
      backgroundColor: scheme.surfaceContainerHigh,
      appBar: AppBar(
        title: Text('${batch.pageCount} page${batch.pageCount == 1 ? '' : 's'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: () => _confirmClear(context, ref),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: batch.pages.length,
        itemBuilder: (context, index) {
          final page = batch.pages[index];
          return _DocumentPageCard(
            index: index,
            page: page,
            totalPages: batch.pages.length,
            onTapFilter: () => context.push('/camera/filter', extra: index),
            onRemove: () {
              ref.read(documentBatchProvider.notifier).removePage(index);
            },
          );
        },
      ),
      bottomNavigationBar: _BottomActionBar(
        pageCount: batch.pages.length,
        onSaveAsPdf: () => context.push('/images/to-pdf'),
        onSaveAsImages: () => _saveAsImages(context, ref, batch.pages),
        onFilterAll: () => context.push('/camera/filter', extra: -1),
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all pages?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(documentBatchProvider.notifier).clearBatch();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsImages(BuildContext context, WidgetRef ref, List<ScannedPage> pages) async {
    final items = <({Uint8List bytes, String fileName})>[];
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      items.add((
        bytes: page.displayBytes,
        fileName: 'scan_page_${i + 1}.jpg',
      ));
    }

    try {
      final results = await saveMultipleImages(items);
      if (!context.mounted) return;

      if (results.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${results.first.fileName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${results.length} images saved'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Share',
              onPressed: () {
                final xFiles = results
                    .where((r) => r.path != null)
                    .map((r) => XFile(r.path!))
                    .toList();
                if (xFiles.isNotEmpty) {
                  Share.shareXFiles(xFiles, text: 'Scanned pages');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ─── Page Preview Card ──────────────────────────────────────────────────

class _DocumentPageCard extends StatelessWidget {
  const _DocumentPageCard({
    required this.index,
    required this.page,
    required this.totalPages,
    required this.onTapFilter,
    required this.onRemove,
  });

  final int index;
  final ScannedPage page;
  final int totalPages;
  final VoidCallback onTapFilter;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Document page card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: page.imageBytes != null
                  ? Image.memory(
                      page.displayBytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _placeholder(scheme),
                    )
                  : _placeholder(scheme),
            ),
          ),
          const SizedBox(height: 8),
          // Page footer with actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Page number badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${index + 1} / $totalPages',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                if (page.filterType != FilterType.none) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _filterLabel(page.filterType),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Filter button
                IconButton(
                  onPressed: onTapFilter,
                  icon: const Icon(Icons.tune, size: 20),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Filter',
                ),
                // Delete button
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline, size: 20,
                      color: scheme.error),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined,
            size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ─── Bottom Action Bar ──────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.pageCount,
    required this.onSaveAsPdf,
    required this.onSaveAsImages,
    required this.onFilterAll,
  });

  final int pageCount;
  final VoidCallback onSaveAsPdf;
  final VoidCallback onSaveAsImages;
  final VoidCallback onFilterAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              // Filter All
              OutlinedButton.icon(
                onPressed: onFilterAll,
                icon: const Icon(Icons.filter_list, size: 20),
                label: const Text('Filter'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              // Save as Images
              OutlinedButton.icon(
                onPressed: onSaveAsImages,
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('Images'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              // Save as PDF (primary action)
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSaveAsPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 20),
                  label: Text(
                    pageCount > 1 ? 'Save as PDF' : 'Save as PDF',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _filterLabel(FilterType type) {
  switch (type) {
    case FilterType.magicColor:
      return 'Magic Color';
    case FilterType.binarization:
      return 'Binarization';
    case FilterType.shadowRemoval:
      return 'Shadow Removal';
    case FilterType.none:
      return '';
  }
}
