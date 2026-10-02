import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/image_isolate_service.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/platform_image_encoder.dart';
import '../../../core/services/public_storage.dart';
import '../../camera/notifiers/document_batch_notifier.dart';
import '../../format_converter/notifiers/format_converter_notifier.dart'
    show ConvertFormat;
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../services/file_open_service.dart';

/// Modal bottom sheet / dialog displaying full interactive image preview
/// and quick-action tools to modify or export the image.
class FileEditSheet extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<FileEditSheet> createState() => _FileEditSheetState();
}

class _FileEditSheetState extends ConsumerState<FileEditSheet> {
  bool _isBusy = false;
  String? _busyLabel;

  Future<Uint8List?> _readBytes() async {
    final file = File(widget.item.path);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  Future<void> _openCrop(BuildContext context) async {
    final bytes = await _readBytes();
    if (bytes == null) return;

    await ref.read(documentBatchProvider.notifier).clearBatch();
    await ref.read(documentBatchProvider.notifier).startNewBatch();
    await ref.read(documentBatchProvider.notifier).addPageFromPath(widget.item.path);
    if (context.mounted) {
      Navigator.pop(context);
      context.push('/camera/crop', extra: 0);
    }
  }

  Future<void> _openFilter(BuildContext context) async {
    final bytes = await _readBytes();
    if (bytes == null) return;

    await ref.read(documentBatchProvider.notifier).clearBatch();
    await ref.read(documentBatchProvider.notifier).startNewBatch();
    await ref.read(documentBatchProvider.notifier).addPageFromPath(widget.item.path);
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

  Future<void> _resizeImage() async {
    if (_isBusy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E2129),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Resize Image Preset',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded, color: Color(0xFF29B6F6)),
                title: const Text('75% Scale', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '75%'),
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded, color: Color(0xFF00E676)),
                title: const Text('50% Scale (Half Size)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '50%'),
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded, color: Color(0xFFFFA726)),
                title: const Text('25% Scale (Quarter Size)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '25%'),
              ),
              ListTile(
                leading: const Icon(Icons.hd_outlined, color: Color(0xFFAB47BC)),
                title: const Text('Full HD (Max 1920x1080)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, '1080p'),
              ),
              ListTile(
                leading: const Icon(Icons.compress_rounded, color: Color(0xFFFF7043)),
                title: const Text('Smart Compression (Best Quality / Size)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'smart'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    setState(() {
      _isBusy = true;
      _busyLabel = 'Resizing image in background...';
    });

    try {
      final bytes = await _readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read image file');
      }

      int? maxWidth;
      int? maxHeight;
      int quality = 85;

      final probe = await ImageIsolateService.probe(bytes);
      final currentWidth = probe.width > 0 ? probe.width : 1920;
      final currentHeight = probe.height > 0 ? probe.height : 1080;

      if (choice == '75%') {
        maxWidth = (currentWidth * 0.75).round();
        maxHeight = (currentHeight * 0.75).round();
      } else if (choice == '50%') {
        maxWidth = (currentWidth * 0.50).round();
        maxHeight = (currentHeight * 0.50).round();
      } else if (choice == '25%') {
        maxWidth = (currentWidth * 0.25).round();
        maxHeight = (currentHeight * 0.25).round();
      } else if (choice == '1080p') {
        maxWidth = 1920;
        maxHeight = 1080;
      } else if (choice == 'smart') {
        quality = 70;
        maxWidth = (currentWidth * 0.85).round();
      }

      final ext = widget.item.extension.toLowerCase();
      final targetExt = (ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp') ? ext : 'jpg';

      Uint8List? resized;
      if (targetExt == 'webp') {
        resized = await PlatformImageEncoder.encodeWebP(
          bytes,
          quality: quality,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      } else {
        resized = await ImageIsolateService.transform(
          bytes,
          ImageTransformRequest(
            targetExtension: targetExt,
            quality: quality,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
        );
      }

      if (resized == null || resized.isEmpty) {
        throw Exception('Resize failed');
      }

      final base = p.basenameWithoutExtension(widget.item.fileName);
      final fileName = '${base}_resized_${DateTime.now().millisecondsSinceEpoch}.$targetExt';

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.resize,
        entries: [
          OutputEntry.bytes(
            bytes: resized,
            fileName: fileName,
            publicKind: PublicFileKind.image,
          ),
        ],
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      final newSize = await File(saved.first.localPath).length();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image resized (${_formatSize(widget.item.sizeBytes)} → ${_formatSize(newSize)})',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () =>
                Share.shareXFiles([XFile(saved.first.localPath)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resize failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _convertFormat() async {
    if (_isBusy) return;
    final selectedFormat = await showModalBottomSheet<ConvertFormat>(
      context: context,
      backgroundColor: const Color(0xFF1E2129),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Convert to Format',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final fmt in [
                    ConvertFormat.jpg,
                    ConvertFormat.png,
                    ConvertFormat.webp,
                    ConvertFormat.pdf,
                    ConvertFormat.tiff,
                    ConvertFormat.bmp,
                  ])
                    ActionChip(
                      backgroundColor: const Color(0xFF2B303C),
                      label: Text(
                        fmt.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, fmt),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedFormat == null || !mounted) return;

    if (selectedFormat == ConvertFormat.pdf) {
      await _createPdf();
      return;
    }

    setState(() {
      _isBusy = true;
      _busyLabel = 'Converting to ${selectedFormat.label} in background...';
    });

    try {
      final bytes = await _readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read image file');
      }

      Uint8List? converted;
      if (selectedFormat == ConvertFormat.webp) {
        converted = await PlatformImageEncoder.encodeWebP(
          bytes,
          quality: 90,
        );
      } else {
        converted = await ImageIsolateService.transform(
          bytes,
          ImageTransformRequest(
            targetExtension: selectedFormat.extension,
            quality: 90,
          ),
        );
      }

      if (converted == null || converted.isEmpty) {
        throw Exception('Image conversion failed');
      }

      final base = p.basenameWithoutExtension(widget.item.fileName);
      final fileName = '${base}_${DateTime.now().millisecondsSinceEpoch}.${selectedFormat.extension}';

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.convert,
        entries: [
          OutputEntry.bytes(
            bytes: converted,
            fileName: fileName,
            publicKind: PublicFileKind.image,
          ),
        ],
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Converted to ${selectedFormat.label} successfully'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () =>
                Share.shareXFiles([XFile(saved.first.localPath)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conversion failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _createPdf() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyLabel = 'Converting image to PDF in background...';
    });
    try {
      final base = p.basenameWithoutExtension(widget.item.fileName);
      final outPath = await PdfService.instance.createPdfFromImages(
        imagePaths: [widget.item.path],
        outputBaseName: base,
      );

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.imageToPdf,
        entries: [
          OutputEntry.file(
            sourcePath: outPath,
            fileName: p.basename(outPath),
            publicKind: PublicFileKind.document,
          ),
        ],
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Converted to PDF successfully'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () =>
                Share.shareXFiles([XFile(saved.first.localPath)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not convert to PDF: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _compressPdf() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyLabel = 'Compressing PDF in background...';
    });
    try {
      final tempDir = await getTemporaryDirectory();
      final base = p.basenameWithoutExtension(widget.item.fileName);
      final outPath = p.join(
        tempDir.path,
        'pixeltools_${base}_compressed_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await PdfService.compressPdfFile(
        inputPath: widget.item.path,
        outputPath: outPath,
        quality: 0.65,
      );

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.pdfCompress,
        entries: [
          OutputEntry.file(
            sourcePath: outPath,
            fileName: p.basename(outPath),
            publicKind: PublicFileKind.document,
          ),
        ],
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      final newSize = await File(saved.first.localPath).length();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF compressed (${_formatSize(widget.item.sizeBytes)} → ${_formatSize(newSize)})',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () =>
                Share.shareXFiles([XFile(saved.first.localPath)]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not compress PDF: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _splitPdf() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyLabel = 'Splitting PDF pages in background...';
    });
    try {
      final base = p.basenameWithoutExtension(widget.item.fileName);
      final splitPaths = await PdfService.instance.splitPdfAllPages(
        inputPath: widget.item.path,
        outputBaseName: base,
      );

      final entries = splitPaths
          .map((sp) => OutputEntry.file(
                sourcePath: sp,
                fileName: p.basename(sp),
                publicKind: PublicFileKind.document,
              ))
          .toList();

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.pdfSplit,
        entries: entries,
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF split into ${saved.length} page documents'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: saved.isNotEmpty
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () =>
                      Share.shareXFiles([XFile(saved.first.localPath)]),
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not split PDF: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    if (await File(widget.item.path).exists()) {
      Share.shareXFiles([XFile(widget.item.path)], text: widget.item.fileName);
    }
  }

  Future<void> _savePdfPagesAsImages() async {
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
      final baseName = widget.item.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final outputPaths = await PdfService.instance.convertPdfToImages(
        inputPath: widget.item.path,
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
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$savedCount page image(s) saved to Gallery & Files'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
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
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save pages as images: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openPdfViewer(BuildContext context) {
    Navigator.pop(context);
    FileOpenService.open(context, path: widget.item.path, name: widget.item.fileName);
  }

  Future<void> _save(BuildContext context) async {
    if (widget.item.isPdf) {
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
        await FileActions.save(context, [widget.item]);
      } else if (choice == 'images') {
        await _savePdfPagesAsImages();
      }
    } else {
      await FileActions.save(context, [widget.item]);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final newName = await FileActions.promptForName(
      context,
      title: 'Rename File',
      initialValue: widget.item.fileName,
    );
    if (newName == null) return;
    await ref
        .read(operationLibraryProvider.notifier)
        .renameFile(widget.item.id, newName);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete "${widget.item.fileName}"?',
      message: 'This will remove the file from this folder. Gallery copies are not affected.',
    );
    if (!confirmed) return;
    await ref.read(operationLibraryProvider.notifier).deleteFiles([widget.item.id]);
    widget.onDeleted();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                          widget.item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : scheme.onSurface,
                          ),
                        ),
                        Text(
                          '${_formatSize(widget.item.sizeBytes)} · ${_formatDate(widget.item.createdAt)}',
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
                child: widget.item.isPdf
                    ? FutureBuilder<Uint8List?>(
                        future: PdfService.instance.renderPageThumbnail(
                          inputPath: widget.item.path,
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
                            File(widget.item.path),
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
                  if (_isBusy) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              const Color(0xFF00E5FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00E5FF),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _busyLabel ?? 'Processing...',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  if (widget.item.isPdf)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolPill(
                            icon: Icons.photo_library_outlined,
                            label: 'Save Pages as Images',
                            color: const Color(0xFF00E676),
                            onTap: _isBusy
                                ? () {}
                                : () => _savePdfPagesAsImages(),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.visibility_outlined,
                            label: 'Open PDF',
                            color: const Color(0xFF29B6F6),
                            onTap: _isBusy
                                ? () {}
                                : () => _openPdfViewer(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.compress_rounded,
                            label: 'Compress',
                            color: const Color(0xFFFFA726),
                            onTap: _isBusy
                                ? () {}
                                : () => _compressPdf(),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.call_split_rounded,
                            label: 'Split',
                            color: const Color(0xFFFF7043),
                            onTap: _isBusy
                                ? () {}
                                : () => _splitPdf(),
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
                            onTap: _isBusy
                                ? () {}
                                : () => _openCrop(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.tune_rounded,
                            label: 'Filters',
                            color: const Color(0xFFAB47BC),
                            onTap: _isBusy
                                ? () {}
                                : () => _openFilter(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.auto_fix_high_rounded,
                            label: 'Magic Clean',
                            color: const Color(0xFF00E676),
                            onTap: _isBusy
                                ? () {}
                                : () => _openMagicRemove(context),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.photo_size_select_large_rounded,
                            label: 'Resize',
                            color: const Color(0xFFFFA726),
                            onTap: _isBusy
                                ? () {}
                                : () => _resizeImage(),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Convert',
                            color: const Color(0xFFFF7043),
                            onTap: _isBusy
                                ? () {}
                                : () => _convertFormat(),
                          ),
                          const SizedBox(width: 8),
                          _ToolPill(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'To PDF',
                            color: const Color(0xFFEF5350),
                            onTap: _isBusy
                                ? () {}
                                : () => _createPdf(),
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
                        label: widget.item.isPdf ? 'Export' : 'Save',
                        onTap: () => _save(context),
                      ),
                      _ActionButton(
                        icon: Icons.drive_file_rename_outline,
                        label: 'Rename',
                        onTap: () => _rename(context),
                      ),
                      _ActionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        isDestructive: true,
                        onTap: () => _delete(context),
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
