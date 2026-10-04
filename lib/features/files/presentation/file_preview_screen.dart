import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/utils/decode_size.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/settings/app_settings.dart';
import '../../../features/image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/utils/image_saver.dart';

class FilePreviewScreen extends ConsumerStatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  final List<EditHistoryItem> items;
  final int initialIndex;

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<EditHistoryItem> _items;
  late bool _isPageGroup;

  @override
  void initState() {
    super.initState();
    final selected =
        widget.items[widget.initialIndex.clamp(0, widget.items.length - 1)];
    final retainedPages = selected.pagePaths;
    if (retainedPages != null && retainedPages.isNotEmpty) {
      // Camera-scan keeps and image-to-PDF outputs: swipe stays scoped to
      // this file's own pages only, never into the next different file.
      _isPageGroup = true;
      _items = retainedPages
          .map((path) => EditHistoryItem(
                fileName: path.split(Platform.pathSeparator).last,
                toolUsed: selected.toolUsed,
                editedAt: selected.editedAt,
                filePath: path,
                thumbnailPath: path,
                toolIcon: selected.toolIcon,
              ))
          .toList();
      _currentIndex = 0;
    } else {
      // Single file scope: preview shows only the opened file.
      _isPageGroup = false;
      _items = [selected];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  EditHistoryItem get _currentItem => _items[_currentIndex];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final total = _items.length;
    final isPdf = _currentItem.fileName.toLowerCase().endsWith('.pdf');

    return Scaffold(
      backgroundColor: isDark ? Colors.black : scheme.surface,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : scheme.surface,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDark ? Colors.white : scheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentItem.fileName,
              style: TextStyle(
                color: isDark ? Colors.white : scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolBadge(tool: _currentItem.toolUsed),
                  const SizedBox(width: 8),
                  Text(
                    _currentItem.timeAgo,
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              color: isDark ? Colors.white : scheme.onSurface,
            ),
            tooltip: 'Rename',
            onPressed: _renameCurrentFile,
          ),
          if (total > 1)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentIndex + 1} of $total',
                style: TextStyle(
                  color: isDark ? Colors.white : scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        itemCount: total,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (_, index) => _PreviewContent(item: _items[index]),
      ),
      bottomNavigationBar: _buildBottomBar(isPdf),
    );
  }

  Widget _buildBottomBar(bool isPdf) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final actions = <_ActionSpec>[
      _ActionSpec(
        icon: isPdf ? Icons.file_upload_outlined : Icons.save_alt_rounded,
        label: isPdf ? 'Export' : 'Save',
        onTap: _saveOrExportFile,
      ),
      if (isPdf)
        _ActionSpec(
          icon: Icons.photo_library_outlined,
          label: 'To Images',
          onTap: _exportPdfPagesAsImages,
        ),
      if (_isPageGroup)
        _ActionSpec(
          icon: Icons.picture_as_pdf_outlined,
          label: 'To PDF',
          onTap: _exportGroupToPdf,
        ),
      _ActionSpec(
        icon: Icons.edit_outlined,
        label: 'Rename',
        onTap: _renameCurrentFile,
      ),
      _ActionSpec(
        icon: Icons.share_rounded,
        label: 'Share',
        onTap: _shareFile,
      ),
      _ActionSpec(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        color: isDark ? Colors.redAccent : scheme.error,
        onTap: _deleteFile,
      ),
    ];

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF1A1A1A) : scheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color(0xFF2A2A2A)
                : scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Share the bar width evenly between the actions and tighten the
          // side padding as the slots get narrower, so every option stays
          // fully on screen on small phones, landscape and large fonts.
          final itemWidth = constraints.maxWidth / actions.length;
          final horizontalPadding = ((itemWidth - 56) / 2).clamp(2.0, 16.0);
          return Row(
            children: [
              for (final action in actions)
                Expanded(
                  child: _ActionButton(
                    icon: action.icon,
                    label: action.label,
                    color: action.color,
                    horizontalPadding: horizontalPadding,
                    onTap: action.onTap,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _renameCurrentFile() async {
    final item = _currentItem;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initialName: item.fileName),
    );

    if (newName != null && newName.isNotEmpty && newName != item.fileName) {
      final success = await ref
          .read(editHistoryProvider.notifier)
          .renameEntry(item, newName);
      if (mounted) {
        if (success) {
          setState(() {
            _items[_currentIndex] = item.copyWith(fileName: newName);
          });
          _showSnack('Renamed to "$newName"');
        } else {
          _showSnack('Failed to rename file');
        }
      }
    }
  }

  /// Sends a kept page group (camera scan / image-to-PDF sources) into the
  /// Image-to-PDF flow so it can be exported later from Files.
  Future<void> _exportGroupToPdf() async {
    final notifier = ref.read(imageToPdfProvider.notifier);
    notifier.clearAll();
    var added = 0;
    for (final item in _items) {
      final path = item.filePath ?? item.thumbnailPath;
      if (path == null || path.isEmpty) continue;
      if (!await File(path).exists()) continue;
      await notifier.addImageFromPath(path);
      added++;
    }
    if (!mounted) return;
    if (added == 0) {
      _showSnack('No pages available for PDF export');
      return;
    }
    context.push('/images/to-pdf');
  }

  Future<void> _saveOrExportFile() async {
    final item = _currentItem;
    final isPdf = item.fileName.toLowerCase().endsWith('.pdf');
    final path = item.filePath ?? item.thumbnailPath;
    if (path == null || path.isEmpty) {
      _showSnack('No file to save');
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        _showSnack('File not found on storage');
        return;
      }

      if (isPdf) {
        if (Platform.isAndroid) {
          // Scoped storage: publish through MediaStore/SAF instead of a raw
          // write into shared storage.
          final destination = await PublicStorage.publishFile(
            sourcePath: path,
            fileName: item.fileName,
            kind: PublicFileKind.document,
          );
          if (mounted) _showSnack('Saved to $destination');
        } else {
          final saveDir =
              await ref.read(appSettingsProvider.notifier).getSaveDirectory();
          final destPath = '${saveDir.path}/${item.fileName}';
          if (file.path != destPath) {
            await file.copy(destPath);
          }
          if (mounted) _showSnack('Exported PDF to ${saveDir.path}');
        }
      } else {
        if (Platform.isAndroid) {
          final destination = await PublicStorage.publishFile(
            sourcePath: file.path,
            fileName: item.fileName,
            kind: PublicFileKind.image,
          );
          if (mounted) _showSnack('Saved to $destination');
        } else {
          final bytes = await file.readAsBytes();
          await saveImageBytes(bytes, fileName: item.fileName);
          if (mounted) _showSnack('Saved to gallery');
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    }
  }

  Future<void> _exportPdfPagesAsImages() async {
    final item = _currentItem;
    final path = item.filePath ?? item.thumbnailPath;
    if (path == null || !File(path).existsSync()) {
      _showSnack('File not found on storage');
      return;
    }

    _showSnack('Saving pages as images...');

    try {
      final base = item.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final outputPaths = await PdfService.instance.convertPdfToImages(
        inputPath: path,
        format: 'jpg',
        outputBaseName: base,
        dpi: 200,
      );

      var saved = 0;
      final savedFiles = <XFile>[];
      for (final p in outputPaths) {
        try {
          final fileName = p.split(Platform.pathSeparator).last;
          await PublicStorage.publishFile(
            sourcePath: p,
            fileName: fileName,
            kind: PublicFileKind.image,
          );
          saved++;
          savedFiles.add(XFile(p));
        } catch (_) {}
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        final controller = messenger.showSnackBar(
          SnackBar(
            content: Text('$saved page image(s) saved to Gallery'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: savedFiles.isNotEmpty
                ? SnackBarAction(
                    label: 'Share',
                    onPressed: () => Share.shareXFiles(savedFiles),
                  )
                : null,
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          try {
            controller.close();
          } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    }
  }

  Future<void> _shareFile() async {
    final path = _currentItem.filePath ?? _currentItem.thumbnailPath;

    try {
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await Share.shareXFiles(
            [XFile(path)],
            subject: _currentItem.fileName,
          );
          return;
        }
      }
      if (mounted) _showSnack('File not available for sharing');
    } catch (e) {
      if (mounted) _showSnack('Share failed: $e');
    }
  }

  Future<void> _deleteFile() async {
    final item = _currentItem;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content:
            Text('Remove "${item.fileName}" from history and delete the file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final path = item.filePath ?? item.thumbnailPath;
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}

    if (!mounted) return;

    ref.read(editHistoryProvider.notifier).removeEntry(item);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.grey[900],
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      try {
        controller.close();
      } catch (_) {}
    });
  }
}

class _PreviewContent extends StatefulWidget {
  const _PreviewContent({required this.item});

  final EditHistoryItem item;

  @override
  State<_PreviewContent> createState() => _PreviewContentState();
}

class _PreviewContentState extends State<_PreviewContent> {
  String? _pdfImagePreview;
  bool _isLoadingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadPdfPreviewIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _PreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _loadPdfPreviewIfNeeded();
    }
  }

  Future<void> _loadPdfPreviewIfNeeded() async {
    final isPdf = widget.item.fileName.toLowerCase().endsWith('.pdf');
    if (!isPdf) return;

    final existingThumb = widget.item.thumbnailPath;
    if (existingThumb != null &&
        existingThumb.isNotEmpty &&
        File(existingThumb).existsSync() &&
        !existingThumb.toLowerCase().endsWith('.pdf')) {
      if (mounted) setState(() => _pdfImagePreview = existingThumb);
      return;
    }

    final pdfPath = widget.item.filePath;
    if (pdfPath != null && File(pdfPath).existsSync()) {
      setState(() => _isLoadingPdf = true);
      final thumb = await PdfService.instance.renderPdfThumbnail(pdfPath);
      if (mounted) {
        setState(() {
          _pdfImagePreview = thumb;
          _isLoadingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isPdf = item.fileName.toLowerCase().endsWith('.pdf');
    final thumb = item.thumbnailPath;
    final filePath = item.filePath;

    if (!isPdf) {
      final imagePath =
          (thumb != null && thumb.isNotEmpty && File(thumb).existsSync())
              ? thumb
              : (filePath != null &&
                      filePath.isNotEmpty &&
                      File(filePath).existsSync())
                  ? filePath
                  : null;

      if (imagePath != null) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                    cacheWidth: zoomDecodeWidthFor(context),
                    errorBuilder: (_, __, ___) => _buildPlaceholder(item, true),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    } else {
      // PDF page 1 preview
      final displayImage = _pdfImagePreview ??
          ((thumb != null &&
                  thumb.isNotEmpty &&
                  !thumb.toLowerCase().endsWith('.pdf') &&
                  File(thumb).existsSync())
              ? thumb
              : null);

      if (displayImage != null && File(displayImage).existsSync()) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image.file(
                      File(displayImage),
                      fit: BoxFit.contain,
                      cacheWidth: zoomDecodeWidthFor(context),
                      errorBuilder: (_, __, ___) =>
                          _buildPlaceholder(item, false),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'PDF (Page 1)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (_isLoadingPdf) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
    }

    return SafeArea(
      child: Center(
        child: _buildPlaceholder(item, !isPdf),
      ),
    );
  }

  Widget _buildPlaceholder(EditHistoryItem item, bool isImage) {
    final gradient = isImage
        ? const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)]
        : const [Color(0xFF5B4DFF), Color(0xFF0F9D9A)];
    final icon = isImage ? Icons.image_outlined : Icons.picture_as_pdf_rounded;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 72),
          const SizedBox(height: 16),
          Text(
            item.fileName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.compressionLevel != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.compressionLevel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolBadge extends StatelessWidget {
  const _ToolBadge({required this.tool});

  final String tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tool,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.horizontalPadding = 16,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final clr = color ?? (isDark ? Colors.white : scheme.onSurface);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: clr, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: clr.withValues(alpha: isDark ? 0.8 : 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rename prompt that owns its [TextEditingController].
///
/// Keeping the controller inside the dialog means it is disposed when the
/// route leaves the tree, instead of leaking one controller per rename.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename File'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
