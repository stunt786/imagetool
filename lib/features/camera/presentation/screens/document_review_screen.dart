import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../../shared/services/watermark_helper.dart';
import '../../../../shared/utils/image_saver.dart';
import '../../../image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import '../../models/document_batch.dart';
import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';
import '../../services/document_scanner_service.dart';
import '../widgets/enhance_filters_sheet.dart';

/// Single-page editor shown after ML Kit returns a scanned batch.
///
/// The interaction is intentionally scanner-first: one large active page,
/// a compact filmstrip, and the most useful actions always within reach.
class DocumentReviewScreen extends ConsumerStatefulWidget {
  const DocumentReviewScreen({super.key});

  @override
  ConsumerState<DocumentReviewScreen> createState() =>
      _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends ConsumerState<DocumentReviewScreen> {
  int _selectedIndex = 0;
  bool _isBusy = false;

  Future<void> _addPage() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final result = await DocumentScannerService.scanDocument();
      if (result == null || result.files.isEmpty || !mounted) return;
      final notifier = ref.read(documentBatchProvider.notifier);
      for (final file in result.files) {
        await notifier.addPageFromPath(file.path);
      }
      if (mounted) {
        setState(() => _selectedIndex =
            (ref.read(documentBatchProvider).pages.length - 1).clamp(0, 9999));
      }
    } catch (error) {
      _showError('Could not add page: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _retakePage() async {
    if (_isBusy) return;
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    setState(() => _isBusy = true);
    try {
      final result = await DocumentScannerService.scanDocument();
      if (result != null && result.files.isNotEmpty) {
        await ref.read(documentBatchProvider.notifier).replacePageFromPath(
              _selectedIndex,
              result.files.first.path,
            );
      }
    } catch (error) {
      _showError('Could not retake page: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rotatePage() async {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    final page = batch.pages[_selectedIndex];
    if (!page.isLoaded) return;

    try {
      final decoded = img.decodeImage(page.imageBytes!);
      if (decoded == null) return;
      final rotated = img.copyRotate(decoded, angle: 90);
      final bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
      ref.read(documentBatchProvider.notifier).updatePage(
            _selectedIndex,
            page.copyWith(
              imageBytes: bytes,
              clearFilter: true,
              width: rotated.width,
              height: rotated.height,
            ),
          );
    } catch (error) {
      _showError('Could not rotate page: $error');
    }
  }

  Future<void> _deletePage() async {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;

    if (batch.pages.length == 1) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard scan?'),
          content: const Text('This will discard the scanned page.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (shouldExit == true && mounted) {
        await ref.read(documentBatchProvider.notifier).clearBatch();
        if (mounted) context.go('/tools');
      }
      return;
    }

    await ref.read(documentBatchProvider.notifier).removePage(_selectedIndex);
    if (mounted) {
      setState(() {
        _selectedIndex = _selectedIndex.clamp(
          0,
          ref.read(documentBatchProvider).pages.length - 1,
        );
      });
    }
  }

  void _openCrop() {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    context.push(
      '/camera/perspective',
      extra: {
        'batchId': batch.id,
        'pageIndex': _selectedIndex,
      },
    );
  }

  void _openFilter() {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => EnhanceFiltersSheet(pageIndex: _selectedIndex),
    );
  }

  Future<void> _openMagicRemove() async {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    final page = batch.pages[_selectedIndex];
    final resultBytes = await context.push<Uint8List?>(
      '/camera/magic-remove',
      extra: page.displayBytes,
    );
    if (resultBytes != null && mounted) {
      final decoded = img.decodeImage(resultBytes);
      final w = decoded?.width ?? page.width;
      final h = decoded?.height ?? page.height;
      ref.read(documentBatchProvider.notifier).updatePage(
            _selectedIndex,
            page.copyWith(
              imageBytes: resultBytes,
              clearFilter: true,
              width: w,
              height: h,
            ),
          );
    }
  }

  void _finish() {
    final batch = ref.read(documentBatchProvider);
    if (batch.hasPages) _showFinishOptions(batch.pages);
  }

  void _showFinishOptions(List<ScannedPage> pages) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExportSheet(
        onPdf: () {
          Navigator.pop(context);
          _openPdfExport(pages);
        },
        onImages: () {
          Navigator.pop(context);
          _saveAsImages(pages);
        },
      ),
    );
  }

  Future<void> _openPdfExport(List<ScannedPage> pages) async {
    final notifier = ref.read(imageToPdfProvider.notifier);
    notifier.clearAll();
    for (final page in pages) {
      await notifier.addImageFromPath(page.path);
    }
    if (mounted) context.push('/images/to-pdf');
  }

  Future<void> _saveAsImages(List<ScannedPage> pages) async {
    final settings = ref.read(appSettingsProvider);
    try {
      final results = await saveMultipleImages([
        for (var i = 0; i < pages.length; i++)
          (
            bytes: WatermarkHelper.applyGlobalWatermarkIfNeeded(
              pages[i].displayBytes,
              settings,
            ),
            fileName: 'scan_page_${i + 1}.jpg',
          ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${results.length} scan image(s) saved'),
          behavior: SnackBarBehavior.floating,
          action: results.isNotEmpty
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () {
                    final files = results
                        .where((result) => result.path != null)
                        .map((result) => XFile(result.path!))
                        .toList();
                    if (files.isNotEmpty) Share.shareXFiles(files);
                  },
                )
              : null,
        ),
      );
    } catch (error) {
      _showError('Saving failed: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(documentBatchProvider);
    if (!batch.hasPages) return _buildEmptyState();

    final safeIndex = _selectedIndex.clamp(0, batch.pages.length - 1);
    final page = batch.pages[safeIndex];
    return Scaffold(
      backgroundColor: const Color(0xFF111214),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              pageNumber: safeIndex + 1,
              pageCount: batch.pages.length,
              isBusy: _isBusy,
              onClose: () => _confirmDiscard(batch),
              onDone: _finish,
            ),
            Expanded(
              child: _LargePagePreview(
                page: page,
                isBusy: _isBusy,
                onTap: () => _showFullPreview(page),
              ),
            ),
            _Filmstrip(
              pages: batch.pages,
              selectedIndex: safeIndex,
              onSelect: (index) => setState(() => _selectedIndex = index),
              onAdd: _addPage,
            ),
            _EditorToolbar(
              onCrop: _openCrop,
              onEnhance: _openFilter,
              onMagicRemove: _openMagicRemove,
              onRotate: _rotatePage,
              onRetake: _retakePage,
              onDelete: _deletePage,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        onAdd: _addPage,
        onDone: _finish,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: const Color(0xFF111214),
      body: Center(
        child: FilledButton.icon(
          onPressed: _addPage,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Scan page'),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(DocumentBatch batch) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this scan?'),
        content: Text('${batch.pageCount} scanned page(s) will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      await ref.read(documentBatchProvider.notifier).clearBatch();
      if (mounted) context.go('/tools');
    }
  }

  void _showFullPreview(ScannedPage page) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.memory(page.displayBytes, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close preview',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.pageNumber,
    required this.pageCount,
    required this.isBusy,
    required this.onClose,
    required this.onDone,
  });

  final int pageNumber;
  final int pageCount;
  final bool isBusy;
  final VoidCallback onClose;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          IconButton(
            onPressed: isBusy ? null : onClose,
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Discard scan',
          ),
          const Spacer(),
          Text(
            '$pageNumber / $pageCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: isBusy ? null : onDone,
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _LargePagePreview extends StatelessWidget {
  const _LargePagePreview({
    required this.page,
    required this.isBusy,
    required this.onTap,
  });

  final ScannedPage page;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF111214),
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                page.displayBytes,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.black54, size: 48),
                ),
              ),
            ),
            if (isBusy) const CircularProgressIndicator(color: Colors.white),
            const Positioned(
              bottom: 4,
              right: 6,
              child: Text(
                'Tap to preview',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.pages,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
  });

  final List<ScannedPage> pages;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages.length > oldWidget.pages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: const Color(0xFF1B1C1F),
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: widget.pages.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == widget.pages.length) {
            return _AddPageTile(onTap: widget.onAdd);
          }
          return _Thumbnail(
            page: widget.pages[index],
            index: index,
            selected: widget.selectedIndex == index,
            onTap: () => widget.onSelect(index),
          );
        },
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.page,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final ScannedPage page;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.memory(page.displayBytes, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${index + 1}',
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPageTile extends StatelessWidget {
  const _AddPageTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 58,
        height: 70,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.onCrop,
    required this.onEnhance,
    required this.onMagicRemove,
    required this.onRotate,
    required this.onRetake,
    required this.onDelete,
  });

  final VoidCallback onCrop;
  final VoidCallback onEnhance;
  final VoidCallback onMagicRemove;
  final VoidCallback onRotate;
  final VoidCallback onRetake;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24262A),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(icon: Icons.crop, label: 'Crop', onTap: onCrop),
            _ToolButton(
                icon: Icons.auto_awesome, label: 'Enhance', onTap: onEnhance),
            _ToolButton(
              icon: Icons.auto_fix_high_rounded,
              label: 'Magic Remove',
              onTap: onMagicRemove,
            ),
            _ToolButton(
                icon: Icons.rotate_right, label: 'Rotate', onTap: onRotate),
            _ToolButton(icon: Icons.refresh, label: 'Retake', onTap: onRetake),
            _ToolButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: const Color(0xFFFF7676),
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onAdd,
    required this.onDone,
  });

  final VoidCallback onAdd;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFF111214),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2F80ED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.onPdf, required this.onImages});

  final VoidCallback onPdf;
  final VoidCallback onImages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF25262A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Save scanned document',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          _ExportOption(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Save as PDF',
            subtitle: 'Combine pages into one document',
            onTap: onPdf,
          ),
          const SizedBox(height: 10),
          _ExportOption(
            icon: Icons.photo_library_outlined,
            title: 'Save as images',
            subtitle: 'Save each scanned page separately',
            onTap: onImages,
          ),
        ],
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: Colors.white10,
      leading: Icon(icon, color: Colors.white, size: 30),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white60),
    );
  }
}
