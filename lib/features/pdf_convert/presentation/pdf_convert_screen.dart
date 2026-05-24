import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/pdf_convert_state.dart';
import '../notifiers/pdf_convert_notifier.dart';
import '../widgets/convert_settings_panel.dart';

class PdfConvertScreen extends ConsumerStatefulWidget {
  const PdfConvertScreen({super.key});

  @override
  ConsumerState<PdfConvertScreen> createState() => _PdfConvertScreenState();
}

class _PdfConvertScreenState extends ConsumerState<PdfConvertScreen> {
  bool _showSettings = false;
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
        final state = ref.read(pdfConvertProvider);
        if (!state.hasFile && state.outputPaths.isEmpty) {
          ref.read(pdfConvertProvider.notifier).pickFile(context);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = ref.read(pdfConvertProvider);
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          ref.read(pdfConvertProvider.notifier).clearError();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfConvertProvider);
    final notifier = ref.read(pdfConvertProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Convert PDF'),
        actions: [
          if (state.hasFile)
            IconButton(
              tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
              onPressed: () => setState(() => _showSettings = !_showSettings),
              icon: Icon(_showSettings ? Icons.settings : Icons.settings_outlined),
            ),
          IconButton(
            tooltip: 'Clear',
            onPressed: state.hasFile || state.outputPaths.isNotEmpty || state.publicExportPaths.isNotEmpty
                ? notifier.clear
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSettings)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ConvertSettingsPanel(
                state: state,
                onFormatChanged: notifier.setOutputFormat,
                onDpiChanged: notifier.setDpi,
              ),
            ),
          Expanded(
            child: state.hasFile || state.outputPaths.isNotEmpty
                ? _buildContent(context, state, notifier)
                : _isOneClickOpening
                    ? const Center(child: CircularProgressIndicator())
                    : _buildEmptyState(context, notifier),
          ),
          if (state.hasFile && !state.isProcessing && state.outputPaths.isEmpty && state.publicExportPaths.isEmpty)
            _buildBottomBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PdfConvertNotifier notifier) {
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
                Icons.transform_rounded,
                size: 64,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No PDF selected',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a PDF file to convert',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => notifier.pickFile(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDF'),
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
    PdfConvertState state,
    PdfConvertNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected file card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.selectedFileName ?? 'Selected PDF',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (state.pageCount != null) '${state.pageCount} pages',
                          if (state.selectedFileSize != null)
                            PdfService.formatFileSize(state.selectedFileSize!),
                          '→ ${state.outputFormat.label}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!state.isProcessing && state.outputPaths.isEmpty)
                  TextButton.icon(
                    onPressed: () => notifier.pickFile(context),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Change'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Progress indicator
          if (state.isProcessing) ...[
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8),
            Text(
              'Converting... ${(state.progress * 100).toInt()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Results
          if (state.outputPaths.isNotEmpty) ...[
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
                        'Conversion Complete',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${state.outputPaths.length} file${state.outputPaths.length > 1 ? 's' : ''} created (${state.outputFormat.label})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (state.publicExportPaths.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ready to export — files are in temporary storage.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                  if (state.publicExportPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Saved to:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.publicExportPaths.first.split('/').sublist(0, state.publicExportPaths.first.split('/').length - 1).join('/'),
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

            if (state.publicExportPaths.isEmpty) ...[
              FilledButton.icon(
                onPressed: () => notifier.exportFiles(),
                icon: const Icon(Icons.save_alt),
                label: const Text('Export to Device'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Output files list
            Text(
              'Output Files',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...state.outputPaths.map((path) {
              final fileName = path.split('/').last;
              final icon = _getFormatIcon(state.outputFormat);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fileName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await Share.shareXFiles([XFile(path)]);
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
              );
            }),

            if (state.publicExportPaths.isNotEmpty) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Files Saved'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${state.publicExportPaths.length} files created'),
                          const SizedBox(height: 8),
                          Text(
                            'Location: ${state.publicExportPaths.first.split('/').sublist(0, state.publicExportPaths.first.split('/').length - 1).join('/')}',
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

  IconData _getFormatIcon(ConvertFormat format) {
    switch (format) {
      case ConvertFormat.jpg:
      case ConvertFormat.png:
        return Icons.image;
      case ConvertFormat.txt:
        return Icons.text_snippet;
      case ConvertFormat.docx:
        return Icons.description;
    }
  }

  Widget _buildBottomBar(
    BuildContext context,
    PdfConvertState state,
    PdfConvertNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: FilledButton.icon(
          onPressed: state.canConvert
              ? () async {
                  final result = await notifier.convert();
                  if (result != null && mounted) {
                    ref.read(editHistoryProvider.notifier).addEntry(
                          EditHistoryItem(
                            fileName: state.selectedFileName ?? 'converted.${state.outputFormat.extension}',
                            toolUsed: 'PDF Converter',
                            editedAt: DateTime.now(),
                            toolIcon: Icons.transform_rounded,
                          ),
                        );
                  }
                }
              : null,
          icon: const Icon(Icons.transform_rounded),
          label: Text(state.hasPageInfo
              ? 'Convert ${state.pageCount} page${state.pageCount! > 1 ? 's' : ''} to ${state.outputFormat.label}'
              : 'Convert to ${state.outputFormat.label}'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}
