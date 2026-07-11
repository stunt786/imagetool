import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

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

  List<EditHistoryItem> get _items => widget.items;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
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
        scrollDirection: Axis.vertical,
        itemCount: total,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (_, index) => _buildPreviewPage(_items[index]),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildPreviewPage(EditHistoryItem item) {
    final isImage = !item.fileName.toLowerCase().endsWith('.pdf');
    final thumb = item.thumbnailPath;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: isImage && thumb != null && thumb.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.file(
                      File(thumb),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(item, isImage),
                    ),
                  ),
                )
              : _buildPlaceholder(item, isImage),
        ),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionButton(
            icon: Icons.save_alt_rounded,
            label: 'Save',
            onTap: _saveFile,
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

  Future<void> _saveFile() async {
    final item = _currentItem;
    final thumb = item.thumbnailPath;
    if (thumb == null || thumb.isEmpty) {
      _showSnack('No file to save');
      return;
    }

    try {
      final file = File(thumb);
      if (!await file.exists()) {
        _showSnack('File not found');
        return;
      }

      final bytes = await file.readAsBytes();
      await saveImageBytes(bytes, fileName: item.fileName);

      if (mounted) _showSnack('Saved to gallery');
    } catch (e) {
      if (mounted) _showSnack('Save failed: $e');
    }
  }

  Future<void> _shareFile() async {
    final thumb = _currentItem.thumbnailPath;

    try {
      if (thumb != null && thumb.isNotEmpty) {
        final file = File(thumb);
        if (await file.exists()) {
          await Share.shareXFiles(
            [XFile(thumb)],
            text: 'Shared from PixelTools',
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
        content: Text('Remove "${item.fileName}" from history and delete the file?'),
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
      final thumb = item.thumbnailPath;
      if (thumb != null && thumb.isNotEmpty) {
        final file = File(thumb);
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
        backgroundColor: Colors.grey[900],
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
