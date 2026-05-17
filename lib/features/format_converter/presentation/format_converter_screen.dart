import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/image_saver.dart';
import '../notifiers/format_converter_notifier.dart';

class FormatConverterScreen extends ConsumerStatefulWidget {
  const FormatConverterScreen({super.key});

  @override
  ConsumerState<FormatConverterScreen> createState() =>
      _FormatConverterScreenState();
}

class _FormatConverterScreenState extends ConsumerState<FormatConverterScreen> {
  bool _isPicking = false;

  Future<void> _pickImages() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );

      if (result == null || result.files.isEmpty) return;

      final imageFiles = <Map<String, dynamic>>[];
      for (final file in result.files) {
        if (file.path == null) continue;

        final ext = file.extension?.toLowerCase() ?? '';
        final validExts = {
          'jpg',
          'jpeg',
          'png',
          'webp',
          'gif',
          'bmp',
          'tif',
          'tiff',
          'heic',
          'heif',
          'avif',
        };

        if (!validExts.contains(ext)) continue;

        imageFiles.add({
          'name': file.name,
          'path': file.path!,
          'sizeBytes': file.size,
        });
      }

      if (imageFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No valid image files selected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        await ref
            .read(formatConverterProvider.notifier)
            .addImages(imageFiles);
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
        .where((i) => i.status == ConvertStatus.success && i.convertedBytes != null)
        .toList();

    if (convertedImages.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final items = convertedImages.map((image) {
        final outputName = '${image.baseName}.${state.selectedFormat.extension}';
        return (bytes: image.convertedBytes!, fileName: outputName);
      }).toList();

      await saveMultipleImages(items);

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text('Saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error saving files: $e'),
            backgroundColor: Colors.red,
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
          ? _buildEmptyState(context)
          : Column(
              children: [
                _buildFormatSelector(context, state),
                _buildQualitySlider(context, state),
                _buildImageList(context, state),
                _buildBottomBar(context, state),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
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
  }

  Widget _buildFormatSelector(BuildContext context, FormatConverterState state) {
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
                  ref
                      .read(formatConverterProvider.notifier)
                      .setFormat(format);
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
    final showQuality = state.selectedFormat == ConvertFormat.jpg;

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
    final validImages = state.images
        .where((i) => i.status != ConvertStatus.removed)
        .toList();

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
                    : image.bytes != null
                    ? Image.memory(
                        image.bytes!,
                        fit: BoxFit.cover,
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
    final hasValidImages = pendingCount > 0;
    final hasSuccess = state.successCount > 0;

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
            if (state.isConverting) ...[
              LinearProgressIndicator(
                value: state.progress / 100,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
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
                if (hasSuccess) ...[
                  const SizedBox(width: 10),
                  _ActionIconButton(
                    icon: const Icon(Icons.save_alt_rounded),
                    label: 'Save',
                    onPressed: _saveConvertedImages,
                    theme: theme,
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: theme.colorScheme.onSecondary,
                    badge: state.successCount.toString(),
                  ),
                ],
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
                  await ref
                      .read(formatConverterProvider.notifier)
                      .convertAll();
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
                        'Convert',
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

  FormatConverterState get state =>
      ref.read(formatConverterProvider);
}

class _ActionIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final ThemeData theme;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? badge;

  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.theme,
    this.backgroundColor,
    this.foregroundColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurface;

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
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: fg,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
