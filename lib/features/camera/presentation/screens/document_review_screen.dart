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
        onAddNewPage: () {
          // Pop back to camera to scan new page
          context.go('/camera');
        },
        onFinish: () => _showFinishOptions(context, ref, batch.pages),
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
              // Navigate back to camera after clearing
              context.go('/camera');
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

  void _showFinishOptions(BuildContext context, WidgetRef ref, List<ScannedPage> pages) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _FinishOptionsSheet(
        onSaveAsPdf: () {
          Navigator.pop(context);
          context.push('/images/to-pdf');
        },
        onSaveAsImages: () {
          Navigator.pop(context);
          _saveAsImages(context, ref, pages);
        },
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

// ─── Finish Options Sheet ───────────────────────────────────────────────

class _FinishOptionsSheet extends StatelessWidget {
  const _FinishOptionsSheet({
    required this.onSaveAsPdf,
    required this.onSaveAsImages,
  });

  final VoidCallback onSaveAsPdf;
  final VoidCallback onSaveAsImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Save as',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _OptionTile(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Save as PDF',
            subtitle: 'Combine all pages into a PDF document',
            color: Colors.red,
            onTap: onSaveAsPdf,
          ),
          const SizedBox(height: 12),
          _OptionTile(
            icon: Icons.photo_library_outlined,
            title: 'Save as Images',
            subtitle: 'Save each page as a separate image',
            color: Colors.green,
            onTap: onSaveAsImages,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.9),
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
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
    required this.onAddNewPage,
    required this.onFinish,
    required this.onSaveAsPdf,
    required this.onSaveAsImages,
    required this.onFilterAll,
  });

  final int pageCount;
  final VoidCallback onAddNewPage;
  final VoidCallback onFinish;
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
              // Add New Page button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddNewPage,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New Page'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Finish button (primary action)
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Finish'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.green,
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
