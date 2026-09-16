import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/pdf_service.dart';
import '../../../core/settings/app_settings.dart';
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

  @override
  void initState() {
    super.initState();
    final selected =
        widget.items[widget.initialIndex.clamp(0, widget.items.length - 1)];
    final retainedPages = selected.pagePaths;
    _items = retainedPages != null && retainedPages.isNotEmpty
        ? retainedPages
            .map((path) => EditHistoryItem(
                  fileName: path.split(Platform.pathSeparator).last,
                  toolUsed: selected.toolUsed,
                  editedAt: selected.editedAt,
                  filePath: path,
                  thumbnailPath: path,
                  toolIcon: selected.toolIcon,
                ))
            .toList()
        : List.from(widget.items);
    _currentIndex = retainedPages != null && retainedPages.isNotEmpty
        ? 0
        : widget.initialIndex.clamp(0, _items.length - 1);
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
    final total = _items.length;
    final isPdf = _currentItem.fileName.toLowerCase().endsWith('.pdf');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentItem.fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _ToolBadge(tool: _currentItem.toolUsed),
                const SizedBox(width: 8),
                Text(
                  _currentItem.timeAgo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Rename',
            onPressed: _renameCurrentFile,
          ),
          if (total > 1)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentIndex + 1} of $total',
                style: const TextStyle(
                  color: Colors.white,
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
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionButton(
            icon: isPdf ? Icons.file_upload_outlined : Icons.save_alt_rounded,
            label: isPdf ? 'Export' : 'Save',
            onTap: _saveOrExportFile,
          ),
          _ActionButton(
            icon: Icons.edit_outlined,
            label: 'Rename',
            onTap: _renameCurrentFile,
          ),
          _ActionButton(
            icon: Icons.share_rounded,
            label: 'Share',
            onTap: _shareFile,
          ),
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: Colors.redAccent,
            onTap: _deleteFile,
          ),
        ],
      ),
    );
  }

  Future<void> _renameCurrentFile() async {
    final item = _currentItem;
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
        final saveDir =
            await ref.read(appSettingsProvider.notifier).getSaveDirectory();
        final destPath = '${saveDir.path}/${item.fileName}';
        if (file.path != destPath) {
          await file.copy(destPath);
        }
        if (mounted) _showSnack('Exported PDF to ${saveDir.path}');
      } else {
        final bytes = await file.readAsBytes();
        await saveImageBytes(bytes, fileName: item.fileName);
        if (mounted) _showSnack('Saved to gallery');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey[900],
      ),
    );
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final clr = color ?? Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: clr, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: clr.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
