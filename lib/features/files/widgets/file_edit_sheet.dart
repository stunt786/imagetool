import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/public_storage.dart';
import '../../camera/notifiers/document_batch_notifier.dart';
import '../../image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../services/file_open_service.dart';

/// Modal bottom sheet / dialog displaying full interactive image preview
/// and quick-action tools to modify or export the image.
class FileEditSheet extends ConsumerWidget {
  const FileEditSheet({
    super.key,
    required this.item,
    required this.onDeleted,
  });

  final AppFileItem item;
  final VoidCallback onDeleted;

  static Future<void> show(
    BuildContext context, {
    required AppFileItem item,
    required VoidCallback onDeleted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FileEditSheet(
        item: item,
        onDeleted: onDeleted,
      ),
    );
  }

  Future<Uint8List?> _readBytes() async {
    final file = File(item.path);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  Future<void> _openCrop(BuildContext context, WidgetRef ref) async {
    final bytes = await _readBytes();
    if (bytes == null) return;

    await ref.read(documentBatchProvider.notifier).clearBatch();
    await ref.read(documentBatchProvider.notifier).startNewBatch();
    await ref.read(documentBatchProvider.notifier).addPageFromPath(item.path);
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/camera/crop', extra: 0);
    }
  }

  Future<void> _openFilter(BuildContext context, WidgetRef ref) async {
    final bytes = await _readBytes();
    if (bytes == null) return;

    await ref.read(documentBatchProvider.notifier).clearBatch();
    await ref.read(documentBatchProvider.notifier).startNewBatch();
    await ref.read(documentBatchProvider.notifier).addPageFromPath(item.path);
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/camera/filter', extra: 0);
    }
  }

  Future<void> _openMagicRemove(BuildContext context) async {
    final bytes = await _readBytes();
    if (bytes == null) return;
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/camera/magic-remove', extra: bytes);
    }
  }

  Future<void> _openResize(BuildContext context) async {
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/images/resizer');
    }
  }

  Future<void> _openConvert(BuildContext context) async {
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/images/convert');
    }
  }

  Future<void> _openCreatePdf(BuildContext context, WidgetRef ref) async {
    final bytes = await _readBytes();
    if (bytes == null) return;
    final notifier = ref.read(imageToPdfProvider.notifier);
    notifier.clearAll();
    await notifier.addImageFromBytes(
      bytes: bytes,
      name: item.fileName,
      path: item.path,
    );
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/images/to-pdf');
    }
  }

  Future<void> _share(BuildContext context) async {
    if (await File(item.path).exists()) {
      Share.shareXFiles([XFile(item.path)], text: item.fileName);
    }
  }

  Future<void> _savePdfPagesAsImages(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Saving pages as images...'),
          ],
        ),
        duration: Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final baseName = item.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final outputPaths = await PdfService.instance.convertPdfToImages(
        inputPath: item.path,
        format: 'jpg',
        outputBaseName: baseName,
        dpi: 200,
      );

      var savedCount = 0;
      final savedFiles = <XFile>[];
      for (final filePath in outputPaths) {
        try {
          final fileName = p.basename(filePath);
          await PublicStorage.publishFile(
            sourcePath: filePath,
            fileName: fileName,
            kind: PublicFileKind.image,
          );
          savedCount++;
          savedFiles.add(XFile(filePath));
        } catch (_) {}
      }

      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$savedCount page image(s) saved to Gallery & Files'),
          behavior: SnackBarBehavior.floating,
          action: savedFiles.isNotEmpty
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () => Share.shareXFiles(savedFiles),
                )
              : null,
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save pages as images: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openPdfViewer(BuildContext context) {
    Navigator.pop(context);
    FileOpenService.open(context, path: item.path, name: item.fileName);
  }

  void _openPdfCompress(BuildContext context) {
    Navigator.pop(context);
    context.push('/pdfs/compress', extra: item.path);
  }

  void _openPdfSplit(BuildContext context) {
    Navigator.pop(context);
    context.push('/pdfs/split', extra: item.path);
  }

  Future<void> _save(BuildContext context) async {
    if (item.isPdf) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF22252D),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Color(0xFFEF5350),
                  ),
                  title: const Text(
                    'Export PDF Document',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Save PDF file to device storage',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () => Navigator.pop(ctx, 'pdf'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF00E676),
                  ),
                  title: const Text(
                    'Save Pages as Images',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Convert & save all pages to Gallery',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () => Navigator.pop(ctx, 'images'),
                ),
              ],
            ),
          ),
        ),
      );

      if (!context.mounted) return;
      if (choice == 'pdf') {
        await FileActions.save(context, [item]);
      } else if (choice == 'images') {
        await _savePdfPagesAsImages(context);
      }
    } else {
      await FileActions.save(context, [item]);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final newName = await FileActions.promptForName(
      context,
      title: 'Rename File',
      initialValue: item.fileName,
    );
    if (newName == null) return;
    await ref.read(operationLibraryProvider.notifier).renameFile(item.id, newName);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete "${item.fileName}"?',
      message: 'This will remove the file from this folder. Gallery copies are not affected.',
    );
    if (!confirmed) return;
    await ref.read(operationLibraryProvider.notifier).deleteFiles([item.id]);
    onDeleted();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181B22) : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : scheme.onSurface,
                          ),
                        ),
                        Text(
                          '${_formatSize(item.sizeBytes)} · ${_formatDate(item.createdAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Preview Area
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.isPdf
                    ? FutureBuilder<Uint8List?>(
                        future: PdfService.instance.renderPageThumbnail(
                          inputPath: item.path,
                          pageNumber: 1,
                          maxWidth: 600,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data != null) {
                            return InkWell(
                              onTap: () => _openPdfViewer(context),
                              child: Stack(
                                fit: StackFit.expand,
                                alignment: Alignment.center,
                                children: [
                                  InteractiveViewer(
                                    minScale: 0.8,
                                    maxScale: 4.0,
                                    child: Center(
                                      child: Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.visibility_outlined,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to view PDF',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return InkWell(
                            onTap: () => _openPdfViewer(context),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 64,
                                    color: Color(0xFFE53935),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'PDF Document · Tap to View',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.file(
                            File(item.path),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 48,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),

            // Tools and Actions section
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                bottomInset > 0 ? bottomInset + 10 : 20,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14161C)
                    : scheme.surfaceContainerHighest,
                border: const Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'MODIFY WITH TOOLS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (item.isPdf)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolPill(
                            icon: Icons.photo_library_outlined,
                            label: 'Save Pages as Images',
                            color: const Color(0xFF00E676),
                            onTap: () => _savePdfPagesAsImages(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.visibility_outlined,
                            label: 'Open PDF',
                            color: const Color(0xFF29B6F6),
                            onTap: () => _openPdfViewer(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.compress_rounded,
                            label: 'Compress',
                            color: const Color(0xFFFFA726),
                            onTap: () => _openPdfCompress(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.call_split_rounded,
                            label: 'Split',
                            color: const Color(0xFFFF7043),
                            onTap: () => _openPdfSplit(context),
                          ),
                        ],
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolPill(
                            icon: Icons.crop_rotate_rounded,
                            label: 'Crop',
                            color: const Color(0xFF29B6F6),
                            onTap: () => _openCrop(context, ref),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.tune_rounded,
                            label: 'Filters',
                            color: const Color(0xFFAB47BC),
                            onTap: () => _openFilter(context, ref),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.auto_fix_high_rounded,
                            label: 'Magic Clean',
                            color: const Color(0xFF00E676),
                            onTap: () => _openMagicRemove(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.photo_size_select_large_rounded,
                            label: 'Resize',
                            color: const Color(0xFFFFA726),
                            onTap: () => _openResize(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Convert',
                            color: const Color(0xFFFF7043),
                            onTap: () => _openConvert(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'To PDF',
                            color: const Color(0xFFEF5350),
                            onTap: () => _openCreatePdf(context, ref),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Colors.white12),
                  const SizedBox(height: 10),
                // File operations row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ActionButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => _share(context),
                    ),
                    _ActionButton(
                      icon: Icons.download_outlined,
                      label: item.isPdf ? 'Export' : 'Save',
                      onTap: () => _save(context),
                    ),
                    _ActionButton(
                      icon: Icons.drive_file_rename_outline,
                      label: 'Rename',
                      onTap: () => _rename(context, ref),
                    ),
                    _ActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      isDestructive: true,
                      onTap: () => _delete(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ToolPill extends StatelessWidget {
  const _ToolPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
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
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFFF5252) : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
