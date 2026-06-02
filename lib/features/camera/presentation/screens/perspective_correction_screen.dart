import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../models/scanned_page.dart';
import '../../notifiers/document_batch_notifier.dart';
import '../../services/perspective_correction_service.dart';
import '../widgets/document_corners_painter.dart';

class PerspectiveCorrectionScreen extends ConsumerStatefulWidget {
  const PerspectiveCorrectionScreen({super.key});

  @override
  ConsumerState<PerspectiveCorrectionScreen> createState() =>
      _PerspectiveCorrectionScreenState();
}

class _PerspectiveCorrectionScreenState
    extends ConsumerState<PerspectiveCorrectionScreen> {
  int? _pageIndex;
  List<Offset> _corners = [];
  int? _draggingCornerIndex;
  bool _isProcessing = false;
  Uint8List? _previewBytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageIndex = GoRouterState.of(context).extra as int?;
    _initCorners();
  }

  void _initCorners() {
    final batch = ref.read(documentBatchProvider);
    if (_pageIndex == null || _pageIndex! >= batch.pages.length) return;

    final page = batch.pages[_pageIndex!];
    if (!page.isLoaded) return;

    final decoded = _getImageDimensions(page.imageBytes!);
    if (decoded == null) return;
    final w = decoded.width.toDouble();
    final h = decoded.height.toDouble();

    _corners = [
      Offset(w * 0.05, h * 0.05),
      Offset(w * 0.95, h * 0.05),
      Offset(w * 0.95, h * 0.95),
      Offset(w * 0.05, h * 0.95),
    ];
  }

  _ImageSize? _getImageDimensions(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image != null) return _ImageSize(image.width, image.height);
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(documentBatchProvider);

    if (_pageIndex == null || _pageIndex! >= batch.pages.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perspective Correction')),
        body: const Center(child: Text('No page selected')),
      );
    }

    final page = batch.pages[_pageIndex!];
    if (!page.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perspective Correction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayBytes = _previewBytes ?? page.imageBytes!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust Corners'),
        actions: [
          TextButton(
            onPressed: _resetCorners,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Correcting perspective...'),
                ],
              ),
            )
          : InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: (_) => _draggingCornerIndex = null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: AspectRatio(
                      aspectRatio: page.width != null && page.width! > 0
                          ? page.width! / page.height!
                          : 1,
                      child: Stack(
                        children: [
                          Image.memory(
                            displayBytes,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          CustomPaint(
                            painter: DocumentCornersPainter(
                              corners: _corners,
                              cornerRadius: 12,
                              strokeWidth: 3,
                              showOverlay: false,
                              cornerColor: Colors.cyanAccent,
                            ),
                            size: Size.infinite,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isProcessing ? null : _applyCorrection,
            icon: const Icon(Icons.transform),
            label: const Text('Correct Perspective'),
          ),
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final touchPos = details.localPosition;
    for (var i = 0; i < _corners.length; i++) {
      if ((touchPos - _corners[i]).distance < 30) {
        _draggingCornerIndex = i;
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingCornerIndex == null) return;
    setState(() {
      _corners[_draggingCornerIndex!] = details.localPosition;
    });
  }

  void _resetCorners() {
    setState(_initCorners);
  }

  Future<void> _applyCorrection() async {
    final batchState = ref.read(documentBatchProvider);
    if (_pageIndex == null || _pageIndex! >= batchState.pages.length) return;

    final page = batchState.pages[_pageIndex!];
    if (!page.isLoaded) return;

    setState(() => _isProcessing = true);

    try {
      final result = await PerspectiveCorrectionService.correct(
        bytes: page.imageBytes!,
        srcPoints: _corners,
        targetWidth: page.width,
        targetHeight: page.height,
      );

      if (result != null && mounted) {
        final correctedPage = page.copyWith(
          imageBytes: result.bytes,
          filteredBytes: null,
          filterType: FilterType.none,
          width: result.width,
          height: result.height,
          correctionCorners: List.from(_corners),
          isCorrectionApplied: true,
          clearFilter: true,
        );

        ref.read(documentBatchProvider.notifier).updatePage(
              _pageIndex!,
              correctedPage,
            );

        setState(() {
          _previewBytes = result.bytes;
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perspective corrected'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Correction failed'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _ImageSize {
  const _ImageSize(this.width, this.height);
  final int width;
  final int height;
}
