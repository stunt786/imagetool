import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_review_service.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/image_to_pdf_state.dart';
import '../notifiers/image_to_pdf_notifier.dart';
import '../widgets/image_thumbnail_card.dart';
import '../widgets/pdf_settings_panel.dart';

class ImageToPdfScreen extends ConsumerStatefulWidget {
  const ImageToPdfScreen({super.key});

  @override
  ConsumerState<ImageToPdfScreen> createState() => _ImageToPdfScreenState();
}

class _ImageToPdfScreenState extends ConsumerState<ImageToPdfScreen> {
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
        final state = ref.read(imageToPdfProvider);
        if (state.images.isEmpty) {
          ref.read(imageToPdfProvider.notifier).pickImages(context);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageToPdfProvider);
    final notifier = ref.read(imageToPdfProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image to PDF'),
        centerTitle: true,
        actions: [
          if (state.images.isNotEmpty)
            IconButton(
              tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
              onPressed: () {
                setState(() {
                  _showSettings = !_showSettings;
                });
              },
              icon: Icon(
                  _showSettings ? Icons.settings : Icons.settings_outlined),
            ),
          IconButton(
            tooltip: 'Clear All',
            onPressed: state.images.isEmpty
                ? null
                : () => _showClearDialog(context, notifier),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSettings)
            // Bounded and scrollable: an unbounded settings panel overflows
            // the column in landscape.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: PdfSettingsPanel(
                  settings: state.pageSettings,
                  onSettingsChanged: notifier.updatePageSettings,
                ),
              ),
            ),
          Expanded(
            child: state.images.isEmpty
                ? _isOneClickOpening
                    ? const Center(child: CircularProgressIndicator())
                    : _buildEmptyState(context, notifier)
                : _buildImageGrid(context, state, notifier),
          ),
          if (state.images.isNotEmpty)
            _buildBottomBar(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ImageToPdfNotifier notifier) {
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
            // Fills the viewport width so the icon, texts and button stay
            // centered on any device size instead of hugging the left edge.
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
                      Icons.image_outlined,
                      size: badgeSize,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No images selected',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select images to convert to PDF',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () {
                      notifier.pickImages(context);
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Select Images'),
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

  Widget _buildImageGrid(BuildContext context, ImageToPdfState state,
      ImageToPdfNotifier notifier) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: state.images.length,
      itemBuilder: (context, index) {
        final item = state.images[index];

        return ReorderableDragStartListener(
          key: ValueKey(item.id),
          index: index,
          child: ImageThumbnailCard(
            index: index,
            imageBytes: item.previewBytes ?? item.imageBytes ?? Uint8List(0),
            imageName: item.name,
            imageSize: item.sizeBytes,
            totalImages: state.images.length,
            isLoading: item.isLoading,
            onRemove: () => notifier.removeImage(index),
            onSwapBefore:
                index > 0 ? () => notifier.swapImage(index, index - 1) : null,
            onSwapAfter: index < state.images.length - 1
                ? () => notifier.swapImage(index, index + 1)
                : null,
            isDragging: false,
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, ImageToPdfState state,
      ImageToPdfNotifier notifier) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isLoadingImages) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Loading images ${state.loadedCount} of ${state.loadTotal}...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${state.loadProgress.toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: state.loadProgress / 100,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 10),
            ],
            if (state.isGenerating)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.statusText ?? 'Generating PDF...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(state.progress * 100).toInt()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (state.canCancel)
                        TextButton(
                          onPressed: notifier.cancelGeneration,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => notifier.pickImages(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: state.isLoadingImages
                          ? null
                          : () => _generatePdf(context, notifier),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Generate & Save PDF'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePdf(
      BuildContext context, ImageToPdfNotifier notifier) async {
    // Snapshot source image paths before generation clears the queue so the
    // Files preview can show per-page image thumbnails scoped to this PDF.
    final sourcePaths = ref
        .read(imageToPdfProvider)
        .images
        .map((item) => item.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final pdfPath = await notifier.generatePdf();

    if (!context.mounted) return;

    if (pdfPath != null) {
      final fileName = pdfPath.split('/').last;
      ref.read(editHistoryProvider.notifier).addEntry(
            EditHistoryItem(
              fileName: fileName,
              toolUsed: 'Image to PDF',
              editedAt: DateTime.now(),
              toolIcon: Icons.picture_as_pdf_rounded,
              filePath: pdfPath,
              thumbnailPath: sourcePaths.isEmpty ? null : sourcePaths.first,
              pagePaths: sourcePaths.isEmpty ? null : sourcePaths,
            ),
          );
      notifier.clearAll();
      _showPDFSavedDialog(context, pdfPath);
      AppReviewService.instance.notifyOperationCompleted(context);
    } else {
      final state = ref.read(imageToPdfProvider);
      if (!context.mounted) return;
      if (state.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showPDFSavedDialog(BuildContext context, String pdfPath) {
    final fileName = pdfPath.split('/').last;
    int fileSize = 0;
    try {
      final file = File(pdfPath);
      if (file.existsSync()) {
        fileSize = file.lengthSync();
      }
    } catch (_) {}
    final sizeStr =
        fileSize > 0 ? '${PdfService.formatFileSize(fileSize)} · ' : '';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
            Navigator.of(dialogCtx).pop();
          }
        });
        return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'PDF Saved',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              fileName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${sizeStr}Saved to Downloads & Files',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await Share.shareXFiles([XFile(pdfPath)]);
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
          ),
        ],
      );
      },
    );
  }

  void _showClearDialog(BuildContext context, ImageToPdfNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Are you sure you want to remove all images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.clearAll();
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
