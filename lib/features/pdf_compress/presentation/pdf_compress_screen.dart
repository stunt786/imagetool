import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/pdf_compress_state.dart';
import '../notifiers/pdf_compress_notifier.dart';

class PdfCompressScreen extends ConsumerStatefulWidget {
  const PdfCompressScreen({super.key});

  @override
  ConsumerState<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends ConsumerState<PdfCompressScreen> {
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
        final state = ref.read(pdfCompressProvider);
        if (!state.hasFile && state.outputPath == null) {
          ref.read(pdfCompressProvider.notifier).pickFile(context);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfCompressProvider);
    final notifier = ref.read(pdfCompressProvider.notifier);

    ref.listen(pdfCompressProvider, (previous, next) {
      if (next.errorMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        ref.read(pdfCompressProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress PDF'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: state.hasFile || state.outputPath != null ? notifier.clear : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.hasFile || state.outputPath != null
                ? _buildContent(context, state, notifier)
                : _isOneClickOpening
                    ? const Center(child: CircularProgressIndicator())
                    : _buildEmptyState(context, notifier),
          ),
          if (state.hasFile && !state.isProcessing && state.outputPath == null)
            _buildBottomBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PdfCompressNotifier notifier) {
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
                Icons.compress_rounded,
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
              'Select a PDF file to compress',
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
    PdfCompressState state,
    PdfCompressNotifier notifier,
  ) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompressionLevelCards(
            selected: state.compressionLevel,
            onLevelChanged: notifier.setCompressionLevel,
          ),
          const SizedBox(height: 20),
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
                      if (state.selectedFileSize != null)
                        Text(
                          state.outputPath != null && state.outputFileSize != null
                              ? '${PdfService.formatFileSize(state.selectedFileSize!)} → ${PdfService.formatFileSize(state.outputFileSize!)}'
                              : PdfService.formatFileSize(state.selectedFileSize!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: state.outputPath != null ? FontWeight.w600 : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!state.isProcessing && state.outputPath == null)
                  TextButton.icon(
                    onPressed: () => notifier.pickFile(context),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Change'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (state.isProcessing) ...[
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8),
            Text(
              'Compressing... ${(state.progress * 100).toInt()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
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
                        'Compression Complete',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.compressionRatio != null)
                    Text(
                      'Reduced by ${state.compressionRatio!.toStringAsFixed(1)}% (${PdfService.formatFileSize(state.selectedFileSize!)} → ${PdfService.formatFileSize(state.outputFileSize!)})',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Saved to:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.outputPath!.split('/').sublist(0, state.outputPath!.split('/').length - 1).join('/'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

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
                        Text('Compressed PDF created'),
                        const SizedBox(height: 8),
                        if (state.compressionRatio != null)
                          Text('Size reduced by ${state.compressionRatio!.toStringAsFixed(1)}%'),
                        const SizedBox(height: 8),
                        Text(
                          'Location: ${state.outputPath!.split('/').sublist(0, state.outputPath!.split('/').length - 1).join('/')}',
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
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    PdfCompressState state,
    PdfCompressNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.hasFile
                ? () async {
                    final result = await notifier.compress();
                    if (result != null && mounted) {
                      ref.read(editHistoryProvider.notifier).addEntry(
                            EditHistoryItem(
                              fileName: state.selectedFileName ?? 'compressed.pdf',
                              toolUsed: 'PDF Compressor',
                              editedAt: DateTime.now(),
                              toolIcon: Icons.compress_rounded,
                              compressionLevel: state.compressionLevel.label,
                            ),
                          );
                    }
                  }
                : null,
            icon: const Icon(Icons.compress_rounded),
            label: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Compress PDF  ',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                    ),
                  ),
                  TextSpan(
                    text: state.compressionLevel.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: scheme.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompressionLevelCards extends StatelessWidget {
  const _CompressionLevelCards({
    required this.selected,
    required this.onLevelChanged,
  });

  final CompressionLevel selected;
  final ValueChanged<CompressionLevel> onLevelChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Compression Level',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                selected.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.0,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: CompressionLevel.values.length,
          itemBuilder: (context, index) {
            final level = CompressionLevel.values[index];
            final isSelected = level == selected;
            return GestureDetector(
              onTap: () => onLevelChanged(level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primary.withValues(alpha: 0.15)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.compress_rounded,
                          size: 16,
                          color: isSelected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          level.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
