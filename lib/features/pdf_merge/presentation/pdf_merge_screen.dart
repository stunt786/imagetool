import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/pdf_merge_state.dart';
import '../notifiers/pdf_merge_notifier.dart';
import '../widgets/pdf_file_list_tile.dart';

class PdfMergeScreen extends ConsumerStatefulWidget {
  const PdfMergeScreen({super.key});

  @override
  ConsumerState<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends ConsumerState<PdfMergeScreen> {
  bool _hasAutoTriggered = false;
  bool _isOneClickOpening = false;

  @override
  void initState() {
    super.initState();
    _isOneClickOpening = ref.read(appSettingsProvider).oneClickOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isOneClickOpening && !_hasAutoTriggered) {
        _hasAutoTriggered = true;
        setState(() => _isOneClickOpening = false);
        final state = ref.read(pdfMergeProvider);
        if (!state.hasFiles && state.outputPath == null) {
          ref.read(pdfMergeProvider.notifier).pickFiles(context);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = ref.read(pdfMergeProvider);
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          ref.read(pdfMergeProvider.notifier).clearError();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfMergeProvider);
    final notifier = ref.read(pdfMergeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
        actions: [
          if (state.hasFiles)
            FilledButton.icon(
              onPressed: () => notifier.pickFiles(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          IconButton(
            tooltip: 'Clear',
            onPressed: state.hasFiles || state.outputPath != null || state.publicExportPath != null ? notifier.clear : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.hasFiles || state.outputPath != null
                ? _buildContent(context, state, notifier)
                : _isOneClickOpening
                    ? const Center(child: CircularProgressIndicator())
                    : _buildEmptyState(context, notifier),
          ),
          if (state.hasFiles && !state.isProcessing && state.outputPath == null && state.publicExportPath == null)
            _buildBottomBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PdfMergeNotifier notifier) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.merge_type_rounded,
                size: 64,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No PDFs selected',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select 2 or more PDF files to merge',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => notifier.pickFiles(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDFs'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PdfMergeState state,
    PdfMergeNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.hasFiles && state.outputPath == null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Drag to reorder files. Merge will combine them in this order.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (state.hasFiles && state.outputPath == null)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: notifier.reorderFiles,
              itemCount: state.files.length,
              itemBuilder: (context, index) {
                final item = state.files[index];
                return PdfFileListTile(
                  key: ValueKey(item.path),
                  item: item,
                  index: index,
                  onRemove: () => notifier.removeFile(index),
                  onReorderStart: () {},
                );
              },
            ),

          if (state.isProcessing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8),
            Text(
              'Merging... ${(state.progress * 100).toInt()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          if (state.outputPath != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.onSecondaryContainer,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Merge Complete',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${state.files.length} files merged successfully',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (state.publicExportPath == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ready to export — file is in temporary storage.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                  if (state.publicExportPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Saved to:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.publicExportPath!.split('/').sublist(0, state.publicExportPath!.split('/').length - 1).join('/'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (state.publicExportPath == null) ...[
              FilledButton.icon(
                onPressed: () => notifier.exportFile(),
                icon: const Icon(Icons.save_alt),
                label: const Text('Export to Device'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 12),
            ],

            Text(
              'Output File',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.outputPath!.split('/').last,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Share.shareXFiles([XFile(state.outputPath!)]);
                    },
                    icon: Icon(
                      Icons.share,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    tooltip: 'Share',
                  ),
                ],
              ),
            ),

            if (state.publicExportPath != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('File Saved'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Merged PDF created from ${state.files.length} files'),
                          const SizedBox(height: 8),
                          Text(
                            'Location: ${state.publicExportPath!.split('/').sublist(0, state.publicExportPath!.split('/').length - 1).join('/')}',
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('View Location'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    PdfMergeState state,
    PdfMergeNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final fileCount = state.files.length;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.canMerge
                ? () async {
                    final result = await notifier.merge();
                    if (result != null && mounted) {
                      ref.read(editHistoryProvider.notifier).addEntry(
                            EditHistoryItem(
                              fileName: 'merged.pdf',
                              toolUsed: 'PDF Merger',
                              editedAt: DateTime.now(),
                              toolIcon: Icons.merge_type_rounded,
                            ),
                          );
                    }
                  }
                : null,
            icon: const Icon(Icons.merge_type_rounded, size: 20),
            label: Flexible(
              child: Text(
                'Merge $fileCount PDF${fileCount > 1 ? 's' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
