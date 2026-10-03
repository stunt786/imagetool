import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/app_review_service.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/settings/app_settings.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/services/file_picker_service.dart';
import '../notifiers/format_converter_notifier.dart';

class FormatConverterScreen extends ConsumerStatefulWidget {
  const FormatConverterScreen({super.key});

  @override
  ConsumerState<FormatConverterScreen> createState() =>
      _FormatConverterScreenState();
}

class _FormatConverterScreenState extends ConsumerState<FormatConverterScreen> {
  bool _isPicking = false;
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
        final state = ref.read(formatConverterProvider);
        if (state.images.isEmpty) {
          _pickImages();
        }
      }
    });
  }

  Future<void> _pickImages() async {
    if (_isPicking) return;
    final currentCount = ref.read(formatConverterProvider).images.length;
    if (currentCount >= 25) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum limit of 25 images reached for conversion.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _isPicking = true);

    try {
      final remaining = 25 - currentCount;
      final service = ref.read(filePickerServiceProvider);
      final pickedFiles = await service.pick(
        context: context,
        target: PickTarget.images,
        allowMultiple: true,
        maxAssets: remaining,
      );

      if (pickedFiles.isEmpty) return;

      if (mounted) {
        ref.read(formatConverterProvider.notifier).addPickedFiles(pickedFiles);
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _saveConvertedImages() async {
    final state = ref.read(formatConverterProvider);
    final convertedImages = state.images
        .where((i) =>
            i.status == ConvertStatus.success && i.convertedBytes != null)
        .toList();

    if (convertedImages.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final isPdf = state.selectedFormat.isPdf;
      final entries = convertedImages.map((image) {
        final outputName =
            '${image.baseName}.${state.selectedFormat.extension}';
        return OutputEntry.bytes(
          bytes: image.convertedBytes!,
          fileName: outputName,
          publicKind: isPdf ? PublicFileKind.document : PublicFileKind.image,
        );
      }).toList();

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.convert,
        entries: entries,
      );

      if (mounted) {
        if (saved.length > 1) {
          ref.read(editHistoryProvider.notifier).addGroup(
                toolName: 'Format Converter',
                toolIcon: Icons.swap_horiz_rounded,
                count: saved.length,
                thumbnailPath: saved.first.localPath,
                filePath: saved.first.localPath,
              );
        } else if (saved.length == 1) {
          ref.read(editHistoryProvider.notifier).addEntry(
                EditHistoryItem(
                  fileName: entries.first.fileName,
                  toolUsed: 'Format Converter',
                  editedAt: DateTime.now(),
                  toolIcon: Icons.swap_horiz_rounded,
                  thumbnailPath: saved.first.localPath,
                  filePath: saved.first.localPath,
                ),
              );
        }

        final destLabel =
            isPdf ? 'Downloads and Files' : 'the gallery and Files';
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                'Saved ${saved.length} file${saved.length > 1 ? 's' : ''} to $destLabel'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        ref.read(formatConverterProvider.notifier).resetStatusForReconversion();
        AppReviewService.instance.notifyOperationCompleted(context);
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error saving files: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(formatConverterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Format Converter'),
        actions: [
          if (state.images.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _showClearDialog(context),
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: state.images.isEmpty
          ? _isOneClickOpening
              ? const Center(child: CircularProgressIndicator())
              : _buildEmptyState(context)
          : Column(
              children: [
                _buildFormatSelector(context, state),
                _buildQualitySlider(context, state),
                Expanded(child: _buildImageList(context, state)),
                _buildBottomBar(context, state),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    // Scrollable and size-aware so the empty state never overflows on a small
    // phone or in landscape.
    return LayoutBuilder(
      builder: (context, constraints) {
        final badgeSize = (constraints.maxHeight * 0.24).clamp(64.0, 120.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48).clamp(0.0, 2000.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                        theme.colorScheme.tertiary.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 60,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Convert Image Formats',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Select multiple images and convert them to JPG, PNG, WebP, BMP, or TIFF format all at once',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _isPicking ? null : _pickImages,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate),
                  label: Text(_isPicking ? 'Selecting...' : 'Select Images'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Supports: JPG, PNG, WebP, GIF, BMP, TIFF, HEIC, AVIF',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormatSelector(
      BuildContext context, FormatConverterState state) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Output Format',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ConvertFormat.values.map((format) {
              final isSelected = state.selectedFormat == format;
              return ChoiceChip(
                label: Text(format.label),
                selected: isSelected,
                onSelected: (_) {
                  ref.read(formatConverterProvider.notifier).setFormat(format);
                },
                selectedColor: theme.colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQualitySlider(BuildContext context, FormatConverterState state) {
    final theme = Theme.of(context);
    final showQuality = state.selectedFormat.isJpeg;

    if (!showQuality) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Quality',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Slider(
              value: state.quality.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              label: '${state.quality}%',
              onChanged: (value) {
                ref
                    .read(formatConverterProvider.notifier)
                    .setQuality(value.round());
              },
            ),
          ),
          Text(
            '${state.quality}%',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageList(BuildContext context, FormatConverterState state) {
    final validImages =
        state.images.where((i) => i.status != ConvertStatus.removed).toList();

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: validImages.length,
        itemBuilder: (context, index) {
          final image = validImages[index];
          return _buildImageCard(context, image, index);
        },
      ),
    );
  }

  Widget _buildImageCard(
    BuildContext context,
    ConvertibleImage image,
    int index,
  ) {
    final theme = Theme.of(context);
    final realIndex = state.images.indexOf(image);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildThumbnail(image),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildInfoChip(
                        context,
                        image.originalFormat,
                        theme.colorScheme.secondaryContainer,
                        theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatFileSize(image.sizeBytes),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (image.width > 0 && image.height > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${image.width}×${image.height}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (image.status == ConvertStatus.success) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Converted: ${formatFileSize(image.convertedSizeBytes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (image.status == ConvertStatus.failed) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.error,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            image.error ?? 'Unknown error',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (image.status == ConvertStatus.converting) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (image.status == ConvertStatus.pending ||
                image.status == ConvertStatus.ready ||
                image.status == ConvertStatus.failed)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  ref
                      .read(formatConverterProvider.notifier)
                      .removeImage(realIndex);
                },
                tooltip: 'Remove',
                iconSize: 20,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ConvertibleImage image) {
    final preview = image.previewBytes ?? image.bytes;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: image.status == ConvertStatus.loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : image.status == ConvertStatus.failed
                ? Icon(
                    Icons.broken_image,
                    color: Colors.red[300],
                    size: 32,
                  )
                : preview != null
                    ? Image.memory(
                        preview,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        cacheWidth: 56,
                        cacheHeight: 56,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.image,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                      )
                    : Icon(
                        Icons.image,
                        color: Colors.grey[400],
                        size: 32,
                      ),
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, FormatConverterState state) {
    final theme = Theme.of(context);
    final pendingCount = state.pendingCount;
    final hasSuccess = state.successCount > 0;
    final hasValidImages = pendingCount > 0 || hasSuccess;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isLoading) ...[
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
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
            ],
            if (state.infoMessage != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.infoMessage!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (state.isConverting) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.convertingStatusText ??
                          'Converting image ${state.currentConvertingIndex} of ${state.totalToConvert}...',
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
                    '${state.progress.toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(formatConverterProvider.notifier)
                        .cancelConversion(),
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
                value: state.progress / 100,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                _ActionIconButton(
                  icon: _isPicking
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: 'Add',
                  onPressed: _isPicking ? null : _pickImages,
                  theme: theme,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildConvertButton(context, state, hasValidImages),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvertButton(
    BuildContext context,
    FormatConverterState state,
    bool hasValidImages,
  ) {
    final theme = Theme.of(context);
    final isConverting = state.isConverting;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 52,
      decoration: BoxDecoration(
        gradient: isConverting
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  Color.lerp(
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                    0.3,
                  )!,
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isConverting
            ? null
            : [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isConverting || !hasValidImages
              ? null
              : () async {
                  if (state.pendingCount > 0) {
                    await ref
                        .read(formatConverterProvider.notifier)
                        .convertAll();
                    if (!mounted) return;
                  }
                  await _saveConvertedImages();
                },
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isConverting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${state.progress.toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swap_horiz_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        state.pendingCount > 0
                            ? 'Convert & Save'
                            : 'Save to Gallery',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (state.pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${state.pendingCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Remove all images from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(formatConverterProvider.notifier).clearAll();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  FormatConverterState get state => ref.read(formatConverterProvider);
}

class _ActionIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final ThemeData theme;

  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final bg = theme.colorScheme.surfaceContainerHighest;
    final fg = theme.colorScheme.onSurface;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(
                color: fg,
                size: 20,
              ),
              child: icon,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
