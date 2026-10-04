import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_review_service.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/utils/deferred_clear.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/pdf_compress_state.dart';
import '../notifiers/pdf_compress_notifier.dart';
import '../widgets/compression_settings_panel.dart';

class PdfCompressScreen extends ConsumerStatefulWidget {
  const PdfCompressScreen({super.key});

  @override
  ConsumerState<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends ConsumerState<PdfCompressScreen> {
  bool _hasAutoTriggered = false;
  bool _isOneClickOpening = false;

  late final PdfCompressNotifier _pdfCompressNotifier;

  @override
  void initState() {
    super.initState();
    _pdfCompressNotifier = ref.read(pdfCompressProvider.notifier);
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
  void dispose() {
    // Release retained file state when the tool closes; deferred so
    // listener notification never runs during tree teardown.
    runDeferredClear(_pdfCompressNotifier.clear);
    super.dispose();
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
            duration: const Duration(seconds: 2),
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
            onPressed: state.hasFile ||
                    state.outputPath != null ||
                    state.publicExportPath != null
                ? notifier.clear
                : null,
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
          if (state.hasFile &&
              !state.isProcessing &&
              state.outputPath == null &&
              state.publicExportPath == null)
            _buildBottomBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, PdfCompressNotifier notifier) {
    final theme = Theme.of(context);

    // Scrollable and size-aware so the empty state never overflows on a small
    // phone or in landscape.
    return LayoutBuilder(
      builder: (context, constraints) {
        final badgeSize = (constraints.maxHeight * 0.22).clamp(44.0, 64.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48).clamp(0.0, 4000.0),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(badgeSize * 0.375),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.compress_rounded,
                      size: badgeSize,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No PDF selected',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompressionSettingsPanel(
                level: state.compressionLevel,
                onLevelChanged: notifier.setCompressionLevel,
                colorQuality: state.colorImageQuality,
                onColorQualityChanged: notifier.setColorImageQuality,
                greyQuality: state.greyImageQuality,
                onGreyQualityChanged: notifier.setGreyImageQuality,
                monoQuality: state.monoImageQuality,
                onMonoQualityChanged: notifier.setMonoImageQuality,
                compressStreams: state.compressStreams,
                onCompressStreamsChanged: notifier.setCompressStreams,
                unembedSimpleFonts: state.unembedSimpleFonts,
                onUnembedSimpleFontsChanged: notifier.setUnembedSimpleFonts,
                unembedComplexFonts: state.unembedComplexFonts,
                onUnembedComplexFontsChanged: notifier.setUnembedComplexFonts,
                unembedUnusualFonts: state.unembedUnusualFonts,
                onUnembedUnusualFontsChanged: notifier.setUnembedUnusualFonts,
                flattenLayers: state.flattenLayers,
                onFlattenLayersChanged: notifier.setFlattenLayers,
                isAdvancedExpanded: state.isAdvancedExpanded,
                onToggleAdvanced: notifier.toggleAdvancedExpanded,
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
                              state.outputPath != null &&
                                      state.outputFileSize != null
                                  ? '${PdfService.formatFileSize(state.selectedFileSize!)} → ${PdfService.formatFileSize(state.outputFileSize!)}'
                                  : PdfService.formatFileSize(
                                      state.selectedFileSize!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: state.outputPath != null
                                    ? FontWeight.w600
                                    : null,
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
                  state.progress < 0.1
                      ? 'Analysing PDF structure...'
                      : state.progress >= 0.85 && state.progress < 0.9
                          ? 'Optimising streams...'
                          : 'Compressing... ${(state.progress * 100).toInt()}%',
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
                          state.compressionRatio! > 0
                              ? 'Reduced by ${state.compressionRatio!.toStringAsFixed(1)}% (${PdfService.formatFileSize(state.selectedFileSize!)} → ${PdfService.formatFileSize(state.outputFileSize!)})'
                              : 'Already compressed at highest level',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (state.note != null &&
                          state.note != 'Already compressed at highest level') ...[
                        const SizedBox(height: 6),
                        Text(
                          state.note!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
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
                          state.publicExportPath!
                              .split('/')
                              .sublist(0,
                                  state.publicExportPath!.split('/').length - 1)
                              .join('/'),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            notifier.clear();
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Done'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await Share.shareXFiles([XFile(state.outputPath!)]);
                          },
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
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
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.hasFile
                ? () async {
                    final result = await notifier.compress();
                    if (result != null && mounted) {
                      final fileName = result.split('/').last;
                      ref.read(editHistoryProvider.notifier).addEntry(
                            EditHistoryItem(
                              fileName: fileName,
                              toolUsed: 'PDF Compressor',
                              editedAt: DateTime.now(),
                              toolIcon: Icons.compress_rounded,
                              compressionLevel: state.compressionLevel.label,
                              filePath: result,
                              thumbnailPath: result,
                            ),
                          );
                      if (context.mounted) {
                        AppReviewService.instance.notifyOperationCompleted(context);
                      }
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
