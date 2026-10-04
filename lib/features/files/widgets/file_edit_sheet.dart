// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/utils/decode_size.dart';
import '../../../core/services/image_isolate_service.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/platform_image_encoder.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../shared/services/watermark_helper.dart';
import '../../camera/presentation/screens/magic_remove_screen.dart';
import '../../format_converter/notifiers/format_converter_notifier.dart'
    show ConvertFormat, convertFormatWorker;
import '../../pdf_compress/models/pdf_compress_state.dart'
    show CompressionLevel;
import '../notifiers/operation_library_notifier.dart';
import '../presentation/file_crop_screen.dart';
import '../services/file_actions.dart';
import '../services/file_open_service.dart';
import 'file_filter_sheet.dart';

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
  late AppFileItem _item;
  int _imageVersion = 0;
  bool _isBusy = false;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  void didUpdateWidget(covariant FileEditSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _item = widget.item;
    }
  }

  Future<Uint8List?> _readBytes() async {
    final file = File(_item.path);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  Future<void> _onImageReplaced(AppFileItem updated, String message) async {
    try {
      await FileImage(File(updated.path)).evict();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _item = updated;
      _imageVersion++;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openCrop() async {
    if (_isBusy) return;
    if (!await File(_item.path).exists()) return;
    if (!mounted) return;

    final updated = await Navigator.of(context).push<AppFileItem?>(
      MaterialPageRoute(
        builder: (_) => FileCropScreen(item: _item),
      ),
    );
    if (updated == null || !mounted) return;
    await _onImageReplaced(updated, 'Image cropped');
  }

  Future<void> _openFilter() async {
    if (_isBusy) return;
    if (!await File(_item.path).exists()) return;
    if (!mounted) return;

    final updated = await FileFilterSheet.show(context, item: _item);
    if (updated == null || !mounted) return;
    await _onImageReplaced(updated, 'Filter applied');
  }

  Future<void> _openMagicRemove() async {
    if (_isBusy) return;
    final bytes = await _readBytes();
    if (bytes == null || !mounted) return;

    // The sheet stays open underneath so cancelling returns the user to the
    // preview instead of dumping them back on the folder grid.
    final cleaned = await Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(
        builder: (_) => MagicRemoveScreen(imageBytes: bytes),
      ),
    );
    if (cleaned == null || !mounted) return;
    if (_sameBytes(cleaned, bytes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing was cleaned in this image'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _busyLabel = 'Saving cleaned image...';
    });
    try {
      Uint8List finalBytes = cleaned;
      final ext = _item.extension.toLowerCase();
      if (ext == 'png' || ext == 'webp' || ext == 'tiff' || ext == 'tif') {
        final converted = await ImageIsolateService.transform(
          cleaned,
          ImageTransformRequest(targetExtension: ext, quality: 95),
        );
        if (converted != null && converted.isNotEmpty) {
          finalBytes = converted;
        }
      }

      final updated = await ref.read(operationStoreProvider).replaceFileBytes(
        fileId: _item.id,
        bytes: finalBytes,
      );

      await ref.read(operationLibraryProvider.notifier).reload();
      if (!mounted) return;
      if (updated != null) {
        await _onImageReplaced(updated, 'Magic clean applied');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Magic clean failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
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

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.lengthInBytes != b.lengthInBytes) return false;
    return listEquals(a, b);
  }

  Future<void> _resizeImage() async {
    if (_isBusy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2129),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height -
                MediaQuery.viewPaddingOf(ctx).top -
                16,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SingleChildScrollView(
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
                    leading: const Icon(Icons.aspect_ratio_rounded,
                        color: Color(0xFF29B6F6)),
                    title: const Text('75% Scale',
                        style: TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, '75%'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio_rounded,
                        color: Color(0xFF00E676)),
                    title: const Text('50% Scale (Half Size)',
                        style: TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, '50%'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio_rounded,
                        color: Color(0xFFFFA726)),
                    title: const Text('25% Scale (Quarter Size)',
                        style: TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, '25%'),
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.hd_outlined, color: Color(0xFFAB47BC)),
                    title: const Text('Full HD (Max 1920x1080)',
                        style: TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, '1080p'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.compress_rounded,
                        color: Color(0xFFFF7043)),
                    title: const Text('Smart Compression (Best Quality / Size)',
                        style: TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, 'smart'),
                  ),
                ],
              ),
            ),
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

      final ext = _item.extension.toLowerCase();
      final targetExt = switch (ext) {
        'png' => 'png',
        'webp' => 'webp',
        'bmp' => 'bmp',
        'tif' || 'tiff' => 'tiff',
        _ => 'jpg',
      };

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

      final oldSize = _item.sizeBytes;
      final updated = await ref.read(operationStoreProvider).replaceFileBytes(
        fileId: _item.id,
        bytes: resized,
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      if (updated != null) {
        await _onImageReplaced(
          updated,
          'Image resized (${_formatSize(oldSize)} → ${_formatSize(updated.sizeBytes)})',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resize failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
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
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2129),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height -
                MediaQuery.viewPaddingOf(ctx).top -
                16,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: SingleChildScrollView(
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
        ),
      ),
    );

    if (selectedFormat == null || !mounted) return;

    setState(() {
      _isBusy = true;
      _busyLabel = 'Converting to ${selectedFormat.label} in background...';
    });

    try {
      final bytes = await _readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read image file');
      }

      AppSettingsState settings;
      try {
        settings = ref.read(appSettingsProvider);
      } catch (_) {
        settings = const AppSettingsState(savePath: '');
      }
      if (WatermarkHelper.cachedIconBytes == null) {
        try {
          await WatermarkHelper.loadIconBytes();
        } catch (_) {}
      }

      final converted = await compute(convertFormatWorker, <String, Object?>{
        'source': bytes,
        'target': selectedFormat.codec,
        'quality': 90,
        'settings': settings,
        'iconBytes': WatermarkHelper.cachedIconBytes,
      });

      if (converted == null || converted.isEmpty) {
        throw Exception('Image conversion failed');
      }

      final base = p.basenameWithoutExtension(_item.fileName);
      final fileName =
          'pixeltools_${base}_${DateTime.now().millisecondsSinceEpoch}.${selectedFormat.extension}';

      await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.convert,
        entries: [
          OutputEntry.bytes(
            bytes: converted,
            fileName: fileName,
            publicKind: PublicFileKind.image,
          ),
        ],
        intoOperationId: _item.operationId,
      );

      await ref.read(operationLibraryProvider.notifier).reload();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Converted to ${selectedFormat.label} and saved to this folder'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conversion failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
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
    final selectedLevel = await showModalBottomSheet<CompressionLevel>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF22252D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _CompressOptionsSheet(),
    );

    if (selectedLevel == null || !mounted) return;

    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyLabel = 'Compressing PDF in background...';
    });
    try {
      final tempDir = await getTemporaryDirectory();
      final base = p.basenameWithoutExtension(_item.fileName);
      final outPath = p.join(
        tempDir.path,
        'pixeltools_${base}_compressed_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await PdfService.compressPdfFile(
        inputPath: _item.path,
        outputPath: outPath,
        quality: selectedLevel.qualityFactor,
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

      Navigator.pop(context);
      ScaffoldMessenger.of(context).clearSnackBars();

      final msg = (newSize >= _item.sizeBytes)
          ? 'Already compressed at highest level'
          : 'PDF compressed (${_formatSize(_item.sizeBytes)} → ${_formatSize(newSize)})';

      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: (newSize < _item.sizeBytes)
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () =>
                      Share.shareXFiles([XFile(saved.first.localPath)]),
                )
              : null,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        try {
          controller.close();
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not compress PDF: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
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
    int totalPages = 1;
    try {
      totalPages = await PdfService.instance.getPageCount(_item.path);
    } catch (_) {}

    if (!mounted) return;

    final result = await showModalBottomSheet<_SplitOptionsResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF22252D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _SplitOptionsSheet(totalPages: totalPages > 0 ? totalPages : 1),
    );

    if (result == null || !mounted) return;

    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyLabel = 'Splitting PDF in background...';
    });
    try {
      final base = p.basenameWithoutExtension(_item.fileName);
      List<String> splitPaths = [];

      switch (result.mode) {
        case _SplitModeType.allPages:
          splitPaths = await PdfService.instance.splitPdfAllPages(
            inputPath: _item.path,
            outputBaseName: base,
          );
          break;
        case _SplitModeType.byChunks:
          splitPaths = await PdfService.instance.splitPdfByChunk(
            inputPath: _item.path,
            pageSize: result.chunkSize,
            outputBaseName: base,
          );
          break;
        case _SplitModeType.pageRange:
          final pages = [
            for (var pNum = result.startPage; pNum <= result.endPage; pNum++)
              pNum
          ];
          final singleOut = await PdfService.instance.extractPages(
            inputPath: _item.path,
            pageNumbers: pages,
            outputBaseName: '${base}_p${result.startPage}-${result.endPage}',
          );
          splitPaths = [singleOut];
          break;
      }

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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF split into ${saved.length} document(s)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: saved.isNotEmpty
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () => Share.shareXFiles(
                      saved.map((s) => XFile(s.localPath)).toList()),
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
          duration: const Duration(seconds: 2),
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
    if (await File(_item.path).exists()) {
      Share.shareXFiles([XFile(_item.path)], text: _item.fileName);
    }
  }

  Future<void> _savePdfPagesAsImages() async {
    int totalPages = 1;
    try {
      totalPages = await PdfService.instance.getPageCount(_item.path);
    } catch (_) {}

    if (!mounted) return;

    final result = await showModalBottomSheet<_PdfToImagesOptionsResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF22252D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _PdfToImagesOptionsSheet(totalPages: totalPages > 0 ? totalPages : 1),
    );

    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
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
      final baseName = _item.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );

      final pageNumbers = result.isAllPages
          ? null
          : [for (var i = result.startPage; i <= result.endPage; i++) i];

      final outputPaths = await PdfService.instance.convertPdfToImages(
        inputPath: _item.path,
        format: result.format,
        outputBaseName: baseName,
        dpi: result.dpi,
        pageNumbers: pageNumbers,
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

      messenger.clearSnackBars();
      if (!mounted) return;
      Navigator.pop(context);

      final controller = messenger.showSnackBar(
        SnackBar(
          content: Text('$savedCount page image(s) saved to Gallery & Files'),
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
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save pages as images: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openPdfViewer(BuildContext context) {
    Navigator.pop(context);
    FileOpenService.open(context,
        path: _item.path, name: _item.fileName);
  }

  Future<void> _save(BuildContext context) async {
    final ext = _item.extension.toLowerCase();
    final isTiff = ext == 'tiff' || ext == 'tif';

    if (_item.isPdf) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
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
        await FileActions.save(context, [_item]);
      } else if (choice == 'images') {
        await _savePdfPagesAsImages();
      }
    } else if (isTiff) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
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
                    Icons.file_download_outlined,
                    color: Color(0xFF29B6F6),
                  ),
                  title: const Text(
                    'Export TIFF File',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Save original raw TIFF file to device storage',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () => Navigator.pop(ctx, 'export'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF00E676),
                  ),
                  title: const Text(
                    'Save to Photos / Gallery (JPG)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Convert & save viewable image to Gallery',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
              ],
            ),
          ),
        ),
      );

      if (!context.mounted) return;
      if (choice == 'export') {
        await FileActions.exportFile(context, _item);
      } else if (choice == 'gallery') {
        await FileActions.save(context, [_item]);
      }
    } else {
      await FileActions.save(context, [_item]);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final newName = await FileActions.promptForName(
      context,
      title: 'Rename File',
      initialValue: _item.fileName,
    );
    if (newName == null) return;
    await ref
        .read(operationLibraryProvider.notifier)
        .renameFile(_item.id, newName);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete "${_item.fileName}"?',
      message:
          'This will remove the file from this folder. Gallery copies are not affected.',
    );
    if (!confirmed) return;
    await ref
        .read(operationLibraryProvider.notifier)
        .deleteFiles([_item.id]);
    widget.onDeleted();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    // Bottom menu bar height in AppShell: 84.0 + math.max(10.0, bottomPadding)
    final bottomMenuHeight = 84.0 + math.max(10.0, bottomPadding);
    final topPadding = MediaQuery.paddingOf(context).top;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Available height strictly above the bottom menu bar and below the top status bar:
    final maxAvailableHeight = math.max(
      200.0,
      screenHeight - bottomMenuHeight - topPadding - 16,
    );
    final ext = _item.extension.toLowerCase();
    final isTiff =
        ext == 'tiff' || ext == 'tif' || _item.mimeType == 'image/tiff';

    return Container(
      margin: EdgeInsets.fromLTRB(10, 0, 10, bottomMenuHeight + 8),
      constraints: BoxConstraints(
        maxHeight: maxAvailableHeight,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181B22) : scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
                          _item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : scheme.onSurface,
                          ),
                        ),
                        Text(
                          '${_formatSize(_item.sizeBytes)} · ${_formatDate(_item.createdAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? Colors.white60
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                    ),
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
                child: _item.isPdf
                    ? FutureBuilder<Uint8List?>(
                        future: PdfService.instance.renderPageThumbnail(
                          inputPath: _item.path,
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
                                        cacheWidth: zoomDecodeWidthFor(context),
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
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
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
                            ),
                          );
                        },
                      )
                    : isTiff
                        ? FutureBuilder<String?>(
                            key: ValueKey('${_item.path}_$_imageVersion'),
                            future: ThumbnailService.instance.thumbnailFor(
                              _item.path,
                              maxSide: 2048,
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00E5FF),
                                  ),
                                );
                              }
                              final thumbPath = snapshot.data;
                              if (thumbPath != null &&
                                  File(thumbPath).existsSync()) {
                                return InteractiveViewer(
                                  minScale: 0.8,
                                  maxScale: 4.0,
                                  child: Center(
                                    child: Image.file(
                                      File(thumbPath),
                                      key: ValueKey(
                                          '${thumbPath}_$_imageVersion'),
                                      fit: BoxFit.contain,
                                      cacheWidth: zoomDecodeWidthFor(context),
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          size: 48,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  size: 48,
                                  color: Colors.white38,
                                ),
                              );
                            },
                          )
                        : InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.file(
                                File(_item.path),
                                key: ValueKey('${_item.path}_$_imageVersion'),
                                fit: BoxFit.contain,
                                cacheWidth: zoomDecodeWidthFor(context),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14161C)
                    : scheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white10
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
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
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
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
                  if (_item.isPdf)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ToolPill(
                          icon: Icons.photo_library_outlined,
                          label: 'Save Pages as Images',
                          color: const Color(0xFF00E676),
                          enabled: !_isBusy,
                          onTap: () => _savePdfPagesAsImages(),
                        ),
                        _ToolPill(
                          icon: Icons.visibility_outlined,
                          label: 'Open PDF',
                          color: const Color(0xFF29B6F6),
                          enabled: !_isBusy,
                          onTap: () => _openPdfViewer(context),
                        ),
                        _ToolPill(
                          icon: Icons.compress_rounded,
                          label: 'Compress',
                          color: const Color(0xFFFFA726),
                          enabled: !_isBusy,
                          onTap: () => _compressPdf(),
                        ),
                        _ToolPill(
                          icon: Icons.call_split_rounded,
                          label: 'Split',
                          color: const Color(0xFFFF7043),
                          enabled: !_isBusy,
                          onTap: () => _splitPdf(),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ToolPill(
                          icon: Icons.crop_rotate_rounded,
                          label: 'Crop',
                          color: const Color(0xFF29B6F6),
                          enabled: !_isBusy,
                          onTap: () => _openCrop(),
                        ),
                        _ToolPill(
                          icon: Icons.tune_rounded,
                          label: 'Filters',
                          color: const Color(0xFFAB47BC),
                          enabled: !_isBusy,
                          onTap: () => _openFilter(),
                        ),
                        _ToolPill(
                          icon: Icons.auto_fix_high_rounded,
                          label: 'Magic Clean',
                          color: const Color(0xFF00E676),
                          enabled: !_isBusy,
                          onTap: () => _openMagicRemove(),
                        ),
                        _ToolPill(
                          icon: Icons.photo_size_select_large_rounded,
                          label: 'Resize',
                          color: const Color(0xFFFFA726),
                          enabled: !_isBusy,
                          onTap: () => _resizeImage(),
                        ),
                        _ToolPill(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Convert',
                          color: const Color(0xFFFF7043),
                          enabled: !_isBusy,
                          onTap: () => _convertFormat(),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white12
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 10),
                  // File operations row
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: () => _share(context),
                        ),
                      ),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.download_outlined,
                          label: (_item.isPdf || isTiff) ? 'Export' : 'Save',
                          onTap: () => _save(context),
                        ),
                      ),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.drive_file_rename_outline,
                          label: 'Rename',
                          onTap: () => _rename(context),
                        ),
                      ),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          isDestructive: true,
                          onTap: () => _delete(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final color = isDestructive
        ? (isDark ? const Color(0xFFFF5252) : scheme.error)
        : (isDark ? Colors.white : scheme.onSurface);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SplitModeType { allPages, byChunks, pageRange }

class _SplitOptionsResult {
  const _SplitOptionsResult({
    required this.mode,
    this.chunkSize = 5,
    this.startPage = 1,
    this.endPage = 1,
  });

  final _SplitModeType mode;
  final int chunkSize;
  final int startPage;
  final int endPage;
}

class _SplitOptionsSheet extends StatefulWidget {
  const _SplitOptionsSheet({required this.totalPages});

  final int totalPages;

  @override
  State<_SplitOptionsSheet> createState() => _SplitOptionsSheetState();
}

class _SplitOptionsSheetState extends State<_SplitOptionsSheet> {
  _SplitModeType _mode = _SplitModeType.allPages;
  int _chunkSize = 2;
  int _startPage = 1;
  late int _endPage;

  @override
  void initState() {
    super.initState();
    _endPage = widget.totalPages > 0 ? widget.totalPages : 1;
    if (widget.totalPages >= 5) {
      _chunkSize = 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxPages = widget.totalPages > 0 ? widget.totalPages : 1;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height -
              MediaQuery.viewPaddingOf(context).top -
              16,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Split PDF Options',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.totalPages} pages',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RadioListTile<_SplitModeType>(
                  value: _SplitModeType.allPages,
                  groupValue: _mode,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All Pages',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Split each page into an individual PDF file',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  onChanged: (val) {
                    if (val != null) setState(() => _mode = val);
                  },
                ),
                RadioListTile<_SplitModeType>(
                  value: _SplitModeType.byChunks,
                  groupValue: _mode,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('By Page Chunks',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Group every N pages into separate PDF files',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  onChanged: (val) {
                    if (val != null) setState(() => _mode = val);
                  },
                ),
                if (_mode == _SplitModeType.byChunks) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 36, bottom: 8),
                    child: Row(
                      children: [
                        const Text('Pages per chunk: ',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                        for (final s in [2, 3, 5, 10])
                          if (s <= maxPages || s == 2)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text('$s'),
                                selected: _chunkSize == s,
                                onSelected: (_) =>
                                    setState(() => _chunkSize = s),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
                RadioListTile<_SplitModeType>(
                  value: _SplitModeType.pageRange,
                  groupValue: _mode,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom Page Range',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Extract a specific range of pages into one PDF',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  onChanged: (val) {
                    if (val != null) setState(() => _mode = val);
                  },
                ),
                if (_mode == _SplitModeType.pageRange) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 36, bottom: 8),
                    child: Row(
                      children: [
                        const Text('From: ',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                        SizedBox(
                          width: 60,
                          child: DropdownButton<int>(
                            value: _startPage,
                            dropdownColor: const Color(0xFF232730),
                            style: const TextStyle(color: Colors.white),
                            underline: const SizedBox(),
                            items: [
                              for (var i = 1; i <= _endPage; i++)
                                DropdownMenuItem(value: i, child: Text('$i')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _startPage = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text('To: ',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                        SizedBox(
                          width: 60,
                          child: DropdownButton<int>(
                            value: _endPage,
                            dropdownColor: const Color(0xFF232730),
                            style: const TextStyle(color: Colors.white),
                            underline: const SizedBox(),
                            items: [
                              for (var i = _startPage; i <= maxPages; i++)
                                DropdownMenuItem(value: i, child: Text('$i')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _endPage = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _SplitOptionsResult(
                          mode: _mode,
                          chunkSize: _chunkSize,
                          startPage: _startPage,
                          endPage: _endPage,
                        ),
                      );
                    },
                    child: const Text('Split PDF',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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

class _PdfToImagesOptionsResult {
  const _PdfToImagesOptionsResult({
    required this.format,
    required this.dpi,
    required this.isAllPages,
    required this.startPage,
    required this.endPage,
  });

  final String format;
  final int dpi;
  final bool isAllPages;
  final int startPage;
  final int endPage;
}

class _PdfToImagesOptionsSheet extends StatefulWidget {
  const _PdfToImagesOptionsSheet({required this.totalPages});

  final int totalPages;

  @override
  State<_PdfToImagesOptionsSheet> createState() =>
      _PdfToImagesOptionsSheetState();
}

class _PdfToImagesOptionsSheetState extends State<_PdfToImagesOptionsSheet> {
  String _format = 'jpg';
  int _dpi = 200;
  bool _isAllPages = true;
  int _startPage = 1;
  late int _endPage;

  @override
  void initState() {
    super.initState();
    _endPage = widget.totalPages > 0 ? widget.totalPages : 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxPages = widget.totalPages > 0 ? widget.totalPages : 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Save Pages as Images',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.totalPages} pages',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Image Format',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('JPG (Recommended)'),
                  selected: _format == 'jpg',
                  onSelected: (_) => setState(() => _format = 'jpg'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('PNG (Lossless)'),
                  selected: _format == 'png',
                  onSelected: (_) => setState(() => _format = 'png'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Resolution / Quality',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('150 DPI'),
                  selected: _dpi == 150,
                  onSelected: (_) => setState(() => _dpi = 150),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('200 DPI'),
                  selected: _dpi == 200,
                  onSelected: (_) => setState(() => _dpi = 200),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('300 DPI'),
                  selected: _dpi == 300,
                  onSelected: (_) => setState(() => _dpi = 300),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Pages to Save',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Text('All Pages (1-$maxPages)'),
                  selected: _isAllPages,
                  onSelected: (_) => setState(() => _isAllPages = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Custom Range'),
                  selected: !_isAllPages,
                  onSelected: (_) => setState(() => _isAllPages = false),
                ),
              ],
            ),
            if (!_isAllPages) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('From: ',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(
                    width: 60,
                    child: DropdownButton<int>(
                      value: _startPage,
                      dropdownColor: const Color(0xFF232730),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox(),
                      items: [
                        for (var i = 1; i <= _endPage; i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _startPage = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('To: ',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(
                    width: 60,
                    child: DropdownButton<int>(
                      value: _endPage,
                      dropdownColor: const Color(0xFF232730),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox(),
                      items: [
                        for (var i = _startPage; i <= maxPages; i++)
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _endPage = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _PdfToImagesOptionsResult(
                      format: _format,
                      dpi: _dpi,
                      isAllPages: _isAllPages,
                      startPage: _startPage,
                      endPage: _endPage,
                    ),
                  );
                },
                child: const Text('Convert & Save Images',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompressOptionsSheet extends StatefulWidget {
  const _CompressOptionsSheet();

  @override
  State<_CompressOptionsSheet> createState() => _CompressOptionsSheetState();
}

class _CompressOptionsSheetState extends State<_CompressOptionsSheet> {
  CompressionLevel _selected = CompressionLevel.medium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height -
              MediaQuery.viewPaddingOf(context).top -
              16,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compress PDF Options',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                for (final level in CompressionLevel.values)
                  RadioListTile<CompressionLevel>(
                    value: level,
                    groupValue: _selected,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      level.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      level.description,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    onChanged: (val) {
                      if (val != null) setState(() => _selected = val);
                    },
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text(
                      'Compress PDF',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
