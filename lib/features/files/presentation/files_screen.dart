import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/pdf_service.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import 'file_preview_screen.dart';

enum FileCategoryTab { all, images, pdfs, scanned }

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  FileCategoryTab _selectedTab = FileCategoryTab.all;

  bool _isImageItem(EditHistoryItem item) {
    final name = item.fileName.toLowerCase();
    final tool = item.toolUsed.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        tool.contains('resize') ||
        tool.contains('format') ||
        tool.contains('collage');
  }

  bool _isPdfItem(EditHistoryItem item) {
    final name = item.fileName.toLowerCase();
    final tool = item.toolUsed.toLowerCase();
    return name.endsWith('.pdf') ||
        tool.contains('pdf') ||
        tool.contains('merge') ||
        tool.contains('split') ||
        tool.contains('compress');
  }

  bool _isScannedItem(EditHistoryItem item) {
    final tool = item.toolUsed.toLowerCase();
    final name = item.fileName.toLowerCase();
    return tool.contains('scan') || tool.contains('camera') || name.contains('scan');
  }

  List<EditHistoryItem> _filterItems(List<EditHistoryItem> items) {
    switch (_selectedTab) {
      case FileCategoryTab.all:
        return items;
      case FileCategoryTab.images:
        return items.where(_isImageItem).toList();
      case FileCategoryTab.pdfs:
        return items.where(_isPdfItem).toList();
      case FileCategoryTab.scanned:
        return items.where(_isScannedItem).toList();
    }
  }

  Future<void> _showRenameDialog(EditHistoryItem item) async {
    final controller = TextEditingController(text: item.fileName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename File'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'File Name',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a valid file name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.fileName) {
      final success =
          await ref.read(editHistoryProvider.notifier).renameEntry(item, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Renamed to "$newName"' : 'Failed to rename file'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareFile(EditHistoryItem item) async {
    final path = item.filePath ?? item.thumbnailPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(path)], subject: item.fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not share: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top + 72;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 96;
    final allFiles = ref.watch(editHistoryProvider);
    final filteredFiles = _filterItems(allFiles);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [scheme.surface, scheme.surfaceContainer, scheme.surface]
              : [const Color(0xFFF8FAFF), const Color(0xFFFCFAFF), const Color(0xFFFFFCF8)],
        ),
      ),
      child: Stack(
        children: [
          if (!isDark) ...[
            const Positioned(
              top: -70,
              left: -30,
              child: _AmbientOrb(
                size: 220,
                colors: [Color(0xFFE0DEFF), Color(0x00E0DEFF)],
              ),
            ),
            const Positioned(
              top: 260,
              right: -50,
              child: _AmbientOrb(
                size: 200,
                colors: [Color(0xFFD8F6F4), Color(0x00D8F6F4)],
              ),
            ),
          ],
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    Row(
                      children: [
                        Text(
                          'My Files',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: scheme.primaryContainer,
                          ),
                          child: Text(
                            '${filteredFiles.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (allFiles.isNotEmpty)
                          TextButton(
                            onPressed: () => ref.read(editHistoryProvider.notifier).clear(),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryTabs(allFiles, scheme),
                    const SizedBox(height: 16),
                    if (filteredFiles.isEmpty)
                      _EmptyFiles(scheme: scheme, theme: theme, tab: _selectedTab)
                    else
                      ...List.generate(filteredFiles.length, (i) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: i < filteredFiles.length - 1 ? 14 : 0),
                          child: _FileTile(
                            item: filteredFiles[i],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FilePreviewScreen(
                                  items: filteredFiles,
                                  initialIndex: i,
                                ),
                              ),
                            ),
                            onRename: () => _showRenameDialog(filteredFiles[i]),
                            onShare: () => _shareFile(filteredFiles[i]),
                            onDelete: () =>
                                ref.read(editHistoryProvider.notifier).removeEntry(filteredFiles[i]),
                          ),
                        );
                      }),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(List<EditHistoryItem> allItems, ColorScheme scheme) {
    final tabs = [
      (FileCategoryTab.all, 'All', allItems.length),
      (FileCategoryTab.images, 'Images', allItems.where(_isImageItem).length),
      (FileCategoryTab.pdfs, 'PDFs', allItems.where(_isPdfItem).length),
      (FileCategoryTab.scanned, 'Scanned', allItems.where(_isScannedItem).length),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tabs.map((t) {
          final isSelected = _selectedTab == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              label: Text('${t.$2} (${t.$3})'),
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                fontSize: 13,
              ),
              backgroundColor: scheme.surfaceContainerLowest,
              selectedColor: scheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? scheme.primary : scheme.outlineVariant,
                ),
              ),
              onSelected: (_) {
                setState(() => _selectedTab = t.$1);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({
    required this.scheme,
    required this.theme,
    required this.tab,
  });

  final ColorScheme scheme;
  final ThemeData theme;
  final FileCategoryTab tab;

  @override
  Widget build(BuildContext context) {
    final label = switch (tab) {
      FileCategoryTab.all => 'No files yet',
      FileCategoryTab.images => 'No image files yet',
      FileCategoryTab.pdfs => 'No PDF files yet',
      FileCategoryTab.scanned => 'No scanned files yet',
    };

    final subtitle = switch (tab) {
      FileCategoryTab.all => 'Edited images and PDFs will appear here.',
      FileCategoryTab.images => 'Images saved from resize, format converter, or collage appear here.',
      FileCategoryTab.pdfs => 'PDFs saved from merge, split, compress, or convert appear here.',
      FileCategoryTab.scanned => 'Documents scanned from camera appear here.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Icon(Icons.folder_open_rounded, color: scheme.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.item,
    required this.onTap,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
  });

  final EditHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isImage = !item.fileName.toLowerCase().endsWith('.pdf');

    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ThumbnailPreview(item: item, isImage: isImage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ToolBadge(tool: item.toolUsed),
                        if (item.pagePaths != null &&
                            item.pagePaths!.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.pagePaths!.length} pages',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSecondaryContainer,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        Text(
                          item.timeAgo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        if (item.compressionLevel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.compressionLevel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onTertiaryContainer,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (val) {
                  if (val == 'rename') onRename();
                  if (val == 'share') onShare();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(isImage ? Icons.share_rounded : Icons.file_upload_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text(isImage ? 'Share' : 'Export / Share'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPreview extends StatefulWidget {
  const _ThumbnailPreview({required this.item, required this.isImage});

  final EditHistoryItem item;
  final bool isImage;

  @override
  State<_ThumbnailPreview> createState() => _ThumbnailPreviewState();
}

class _ThumbnailPreviewState extends State<_ThumbnailPreview> {
  String? _pdfThumbPath;
  bool _isLoadingPdfThumb = false;

  @override
  void initState() {
    super.initState();
    _loadPdfThumbIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.filePath != widget.item.filePath ||
        oldWidget.item.thumbnailPath != widget.item.thumbnailPath) {
      _loadPdfThumbIfNeeded();
    }
  }

  Future<void> _loadPdfThumbIfNeeded() async {
    if (widget.isImage) return;

    final existingThumb = widget.item.thumbnailPath;
    if (existingThumb != null &&
        existingThumb.isNotEmpty &&
        File(existingThumb).existsSync() &&
        !existingThumb.toLowerCase().endsWith('.pdf')) {
      if (mounted) setState(() => _pdfThumbPath = existingThumb);
      return;
    }

    final pdfPath = widget.item.filePath;
    if (pdfPath != null &&
        pdfPath.toLowerCase().endsWith('.pdf') &&
        File(pdfPath).existsSync()) {
      setState(() => _isLoadingPdfThumb = true);
      final thumb = await PdfService.instance.renderPdfThumbnail(pdfPath);
      if (mounted) {
        setState(() {
          _pdfThumbPath = thumb;
          _isLoadingPdfThumb = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.item.thumbnailPath;
    final filePath = widget.item.filePath;

    if (widget.isImage) {
      final imageSource = (thumb != null && thumb.isNotEmpty)
          ? thumb
          : (filePath != null && filePath.isNotEmpty) ? filePath : null;

      if (imageSource != null && File(imageSource).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File(imageSource),
            width: 90,
            height: 75,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(isImage: true),
          ),
        );
      }
    } else {
      final displayThumb = _pdfThumbPath ??
          ((thumb != null && thumb.isNotEmpty && !thumb.toLowerCase().endsWith('.pdf'))
              ? thumb
              : null);

      if (displayThumb != null && File(displayThumb).existsSync()) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 90,
                height: 75,
                color: Colors.white,
                child: Image.file(
                  File(displayThumb),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPdfFallback(),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      if (_isLoadingPdfThumb) {
        return Container(
          width: 90,
          height: 75,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black12,
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      return _buildPdfFallback();
    }

    return _buildFallback(isImage: widget.isImage);
  }

  Widget _buildPdfFallback() {
    return Container(
      width: 90,
      height: 75,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B4DFF), Color(0xFF0F9D9A)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildFallback({required bool isImage}) {
    final gradient = isImage
        ? const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)]
        : const [Color(0xFF5B4DFF), Color(0xFF0F9D9A)];
    final icon = isImage ? Icons.image_outlined : Icons.picture_as_pdf_rounded;

    return Container(
      width: 90,
      height: 75,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 28)),
    );
  }
}

class _ToolBadge extends StatelessWidget {
  const _ToolBadge({required this.tool});

  final String tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tool,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
