import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../../../core/models/operation_folder.dart';
import '../../../../core/services/operation_recorder.dart';
import '../../../../core/services/operation_store_provider.dart';
import '../../../../core/services/output_saver.dart';
import '../../../../core/services/public_storage.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../shared/notifiers/edit_history_notifier.dart';
import '../../../../shared/services/watermark_helper.dart';
import '../../../image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import '../../models/document_batch.dart';
import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';
import '../../services/batch_storage_service.dart';
import '../../services/document_enhancement_service.dart';
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
      final outcome = await DocumentScannerService.scanDocument();
      if (outcome.isUnavailable && mounted) {
        _showError('The document scanner is not available on this device.');
        return;
      }
      if (!outcome.isSuccess || !mounted) return;
      final notifier = ref.read(documentBatchProvider.notifier);
      for (final file in outcome.files) {
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
      final outcome = await DocumentScannerService.scanDocument();
      if (outcome.isUnavailable && mounted) {
        _showError('The document scanner is not available on this device.');
        return;
      }
      if (outcome.isSuccess) {
        await ref.read(documentBatchProvider.notifier).replacePageFromPath(
              _selectedIndex,
              outcome.files.first.path,
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
      await ref.read(documentBatchProvider.notifier).updatePageAndPersist(
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

  void _exitToHome() {
    if (!mounted) return;
    final shell = StatefulNavigationShell.maybeOf(context);
    if (context.canPop()) {
      context.pop();
    }
    if (shell != null) {
      shell.goBranch(0, initialLocation: true);
    } else {
      context.go('/tools');
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
        _exitToHome();
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
      '/camera/crop',
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

  Future<void> _smartFixPage() async {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    final page = batch.pages[_selectedIndex];
    if (!page.isLoaded || _isBusy) return;

    setState(() => _isBusy = true);
    try {
      final result = await DocumentEnhancementService.smartScanEnhanceDetailed(
          page.imageBytes!);
      if (result != null && mounted) {
        final decoded = img.decodeImage(result.bytes);
        await ref.read(documentBatchProvider.notifier).updatePageAndPersist(
              _selectedIndex,
              page.copyWith(
                imageBytes: result.bytes,
                filteredBytes: null,
                filterType: FilterType.none,
                width: decoded?.width ?? page.width,
                height: decoded?.height ?? page.height,
                clearFilter: true,
              ),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.stages.isEmpty
                ? 'Page already looks clean – nothing to fix.'
                : 'Smart clean applied: ${result.stages.join(', ')}.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _showError('Smart clean failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _autoFlattenPage() async {
    final batch = ref.read(documentBatchProvider);
    if (_selectedIndex >= batch.pages.length) return;
    final page = batch.pages[_selectedIndex];
    if (!page.isLoaded || _isBusy) return;

    setState(() => _isBusy = true);
    try {
      // Flatten straightens paper and clears raised/down parts to make it smooth.
      final flattenedBytes =
          await DocumentEnhancementService.flattenDocument(page.imageBytes!);
      if (flattenedBytes != null && mounted) {
        final decoded = img.decodeImage(flattenedBytes);
        await ref.read(documentBatchProvider.notifier).updatePageAndPersist(
              _selectedIndex,
              page.copyWith(
                imageBytes: flattenedBytes,
                filteredBytes: null,
                filterType: FilterType.none,
                width: decoded?.width ?? page.width,
                height: decoded?.height ?? page.height,
                clearFilter: true,
              ),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page straightened & smoothed (raised/down curves flattened).'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _showError('Flatten failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
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
      await ref.read(documentBatchProvider.notifier).updatePageAndPersist(
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
      isScrollControlled: true,
      builder: (context) => _ExportSheet(
        onPdf: () {
          Navigator.pop(context);
          _navigateAfterCamera(() => _openPdfExport(pages));
        },
        onImages: () {
          Navigator.pop(context);
          _navigateAfterCamera(() => _saveAsImages(pages));
        },
        onKeep: () {
          Navigator.pop(context);
          _navigateAfterCamera(() => _keepInFiles(pages));
        },
      ),
    );
  }

  Future<void> _navigateAfterCamera(VoidCallback action) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) action();
  }

  Future<void> _keepInFiles(List<ScannedPage> pages) async {
    if (pages.isEmpty) {
      _showError('The scanned pages could not be retained.');
      return;
    }
    final batch = ref.read(documentBatchProvider);
    // Create an operation folder to keep all scanned pages together.
    try {
      final session = await OperationRecorder(ref.read(operationStoreProvider))
          .start(OperationKind.scan, expectedItems: pages.length);
      for (var i = 0; i < pages.length; i++) {
        final name = 'scan_page_${(i + 1).toString().padLeft(2, '0')}.jpg';
        await session.saveBytes(pages[i].displayBytes, name);
      }
      await session.complete();
    } catch (_) {}

    var paths = await BatchStorageService.retainBatch(batch.id);
    paths = paths.isEmpty
        ? pages
            .map((page) => page.path)
            .where((path) => path.isNotEmpty)
            .toList(growable: false)
        : paths;
    if (paths.isNotEmpty) {
      ref.read(editHistoryProvider.notifier).addGroup(
            toolName: 'Camera Scan',
            toolIcon: Icons.document_scanner_outlined,
            count: paths.length,
            filePath: paths.first,
            thumbnailPath: paths.first,
            pagePaths: paths,
          );
    }
    await ref.read(documentBatchProvider.notifier).clearBatch();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan saved in Files for later export.')),
    );
    context.go('/pdfs');
  }

  Future<void> _openPdfExport(List<ScannedPage> pages) async {
    final notifier = ref.read(imageToPdfProvider.notifier);
    notifier.clearAll();
    for (final page in pages) {
      await notifier.addImageFromBytes(
        bytes: page.displayBytes,
        name: page.name,
        path: page.path,
      );
    }
    await ref.read(documentBatchProvider.notifier).clearBatch();
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      }
      context.push('/images/to-pdf');
    }
  }

  Future<void> _saveAsImages(List<ScannedPage> pages) async {
    final settings = ref.read(appSettingsProvider);
    try {
      final entries = [
        for (var i = 0; i < pages.length; i++)
          OutputEntry.bytes(
            bytes: WatermarkHelper.applyGlobalWatermarkIfNeeded(
              pages[i].displayBytes,
              settings,
            ),
            fileName: 'scan_page_${(i + 1).toString().padLeft(2, '0')}.jpg',
            publicKind: PublicFileKind.image,
          ),
      ];

      final results = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.scan,
        entries: entries,
      );

      await ref.read(documentBatchProvider.notifier).clearBatch();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${results.length} scan image(s) saved to Gallery & Files'),
          behavior: SnackBarBehavior.floating,
          action: results.isNotEmpty
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () {
                    final files = results
                        .map((result) => XFile(result.localPath))
                        .toList();
                    if (files.isNotEmpty) Share.shareXFiles(files);
                  },
                )
              : null,
        ),
      );
      if (mounted) {
        _exitToHome();
      }
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
    if (!batch.hasPages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _exitToHome();
      });
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final safeIndex = _selectedIndex.clamp(0, batch.pages.length - 1);
    final page = batch.pages[safeIndex];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscard(batch);
      },
      child: Scaffold(
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
                canUndo: batch.undoDepth > 0,
                canRedo: batch.redoDepth > 0,
                onUndo: ref.read(documentBatchProvider.notifier).undo,
                onRedo: ref.read(documentBatchProvider.notifier).redo,
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
                onSmartFix: _smartFixPage,
                onFlatten: _autoFlattenPage,
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
      _exitToHome();
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
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  final int pageNumber;
  final int pageCount;
  final bool isBusy;
  final VoidCallback onClose;
  final VoidCallback onDone;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

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
          IconButton(
            onPressed: isBusy || !canUndo ? null : onUndo,
            icon: const Icon(Icons.undo_rounded, color: Colors.white),
            tooltip: 'Undo edit',
          ),
          IconButton(
            onPressed: isBusy || !canRedo ? null : onRedo,
            icon: const Icon(Icons.redo_rounded, color: Colors.white),
            tooltip: 'Redo edit',
          ),
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
    required this.onSmartFix,
    required this.onFlatten,
    required this.onMagicRemove,
    required this.onRotate,
    required this.onRetake,
    required this.onDelete,
  });

  final VoidCallback onCrop;
  final VoidCallback onEnhance;
  final VoidCallback onSmartFix;
  final VoidCallback onFlatten;
  final VoidCallback onMagicRemove;
  final VoidCallback onRotate;
  final VoidCallback onRetake;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(
              icon: Icons.auto_mode_rounded,
              label: 'Smart Fix',
              iconColor: const Color(0xFF4DA6FF),
              containerColor: const Color(0xFF19324F),
              onTap: onSmartFix,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.straighten_rounded,
              label: 'Flatten',
              iconColor: const Color(0xFF38D9A9),
              containerColor: const Color(0xFF173831),
              onTap: onFlatten,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.crop_rounded,
              label: 'Crop',
              iconColor: Colors.white,
              onTap: onCrop,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.auto_awesome_rounded,
              label: 'Enhance',
              iconColor: const Color(0xFFFFB84D),
              containerColor: const Color(0xFF382C17),
              onTap: onEnhance,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.auto_fix_high_rounded,
              label: 'Magic Remove',
              iconColor: const Color(0xFFC084FC),
              containerColor: const Color(0xFF321E42),
              onTap: onMagicRemove,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.rotate_right_rounded,
              label: 'Rotate',
              iconColor: Colors.white,
              onTap: onRotate,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.refresh_rounded,
              label: 'Retake',
              iconColor: Colors.white70,
              onTap: onRetake,
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              iconColor: const Color(0xFFFF6B6B),
              containerColor: const Color(0xFF3B1B1E),
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
    this.iconColor = Colors.white,
    this.containerColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final Color? containerColor;

  @override
  Widget build(BuildContext context) {
    final effectiveContainerColor =
        containerColor ?? Colors.white.withValues(alpha: 0.08);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: iconColor.withValues(alpha: 0.16),
        highlightColor: iconColor.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SizedBox(
            width: 74,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: effectiveContainerColor,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 74,
                  height: 28,
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
  const _ExportSheet(
      {required this.onPdf, required this.onImages, required this.onKeep});

  final VoidCallback onPdf;
  final VoidCallback onImages;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 20),
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
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ExportButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Save Image',
                  color: const Color(0xFF4DA6FF),
                  onTap: onImages,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ExportButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Save PDF',
                  color: const Color(0xFF34C759),
                  onTap: onPdf,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ExportButton(
                  icon: Icons.check_circle_outline,
                  label: 'Done',
                  color: const Color(0xFFFF9500),
                  onTap: onKeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
