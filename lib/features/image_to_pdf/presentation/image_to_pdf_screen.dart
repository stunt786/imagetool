import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/widgets/ad_banner_wrapper.dart';
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
          InterstitialTracker.instance.trackAction();
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
        actions: [
          if (state.images.isNotEmpty)
            IconButton(
              tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
              onPressed: () {
                setState(() {
                  _showSettings = !_showSettings;
                });
              },
              icon: Icon(_showSettings ? Icons.settings : Icons.settings_outlined),
            ),
          IconButton(
            tooltip: 'Clear All',
            onPressed: state.images.isEmpty ? null : () => _showClearDialog(context, notifier),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: AdBannerWrapper(
        child: Column(
          children: [
            if (_showSettings)
              Padding(
                padding: const EdgeInsets.all(16),
                child: PdfSettingsPanel(
                  settings: state.pageSettings,
                  onSettingsChanged: (settings) {
                    notifier.updatePageSettings(settings);
                  },
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
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ImageToPdfNotifier notifier) {
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
                Icons.image_outlined,
                size: 64,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No images selected',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
                InterstitialTracker.instance.trackAction();
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Select Images'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, ImageToPdfState state, ImageToPdfNotifier notifier) {
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
          key: ValueKey(item.path),
          index: index,
          child: ImageThumbnailCard(
            index: index,
            imageBytes: item.imageBytes ?? Uint8List(0),
            imageName: item.name,
            imageSize: item.sizeBytes,
            totalImages: state.images.length,
            onRemove: () => notifier.removeImage(index),
            onSwapBefore: index > 0
                ? () => notifier.swapImage(index, index - 1)
                : null,
            onSwapAfter: index < state.images.length - 1
                ? () => notifier.swapImage(index, index + 1)
                : null,
            isDragging: false,
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, ImageToPdfState state, ImageToPdfNotifier notifier) {
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
        child: state.isGenerating
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: state.progress),
                  const SizedBox(height: 8),
                  Text(
                    'Generating PDF... ${(state.progress * 100).toInt()}%',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              )
            : Row(
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
                      onPressed: () => _generatePdf(context, notifier),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Generate & Save PDF'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _generatePdf(BuildContext context, ImageToPdfNotifier notifier) async {
    final pdfPath = await notifier.generatePdf();

    if (!context.mounted) return;

    if (pdfPath != null) {
      _showPDFSavedDialog(context, pdfPath);
      InterstitialTracker.instance.trackAction();
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
    final directory = pdfPath.split('/').sublist(0, pdfPath.split('/').length - 1).join('/');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF Saved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'PDF saved successfully!',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File:',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    fileName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Location:',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    directory,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
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
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
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
