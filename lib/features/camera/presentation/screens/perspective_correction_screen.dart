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
    if (_corners.isNotEmpty) return;
    _corners = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final image = _getImageDimensions(displayBytes);
                final imageSize = Size(
                  (image?.width ?? page.width ?? 1).toDouble(),
                  (image?.height ?? page.height ?? 1).toDouble(),
                );
                final fitted = applyBoxFit(
                  BoxFit.contain,
                  imageSize,
                  constraints.biggest,
                );
                final imageRect = Alignment.center.inscribe(
                  fitted.destination,
                  Offset.zero & constraints.biggest,
                );
                final displayCorners = _corners
                    .map((corner) => Offset(
                          imageRect.left + corner.dx * imageRect.width,
                          imageRect.top + corner.dy * imageRect.height,
                        ))
                    .toList();

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _onPanStart(details, imageRect, displayCorners),
                  onPanUpdate: (details) => _onPanUpdate(details, imageRect),
                  onPanEnd: (_) => _draggingCornerIndex = null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fromRect(
                        rect: imageRect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child:
                              Image.memory(displayBytes, fit: BoxFit.contain),
                        ),
                      ),
                      CustomPaint(
                        painter: DocumentCornersPainter(
                          corners: displayCorners,
                          cornerRadius: 18,
                          strokeWidth: 3,
                          showOverlay: true,
                          cornerColor: Colors.cyanAccent,
                          overlayColor: Colors.black,
                        ),
                        size: Size.infinite,
                      ),
                    ],
                  ),
                );
              },
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

  void _onPanStart(
      DragStartDetails details, Rect imageRect, List<Offset> displayCorners) {
    final touchPos = details.localPosition;
    var closestDistance = 48.0;
    for (var i = 0; i < displayCorners.length; i++) {
      final distance = (touchPos - displayCorners[i]).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
        _draggingCornerIndex = i;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Rect imageRect) {
    if (_draggingCornerIndex == null) return;
    final point = details.localPosition;
    final normalized = Offset(
      ((point.dx - imageRect.left) / imageRect.width).clamp(0.02, 0.98),
      ((point.dy - imageRect.top) / imageRect.height).clamp(0.02, 0.98),
    );
    setState(() {
      _corners[_draggingCornerIndex!] = normalized;
    });
  }

  void _resetCorners() {
    setState(() {
      _corners = [
        const Offset(0.05, 0.05),
        const Offset(0.95, 0.05),
        const Offset(0.95, 0.95),
        const Offset(0.05, 0.95),
      ];
      _draggingCornerIndex = null;
    });
  }

  Future<void> _applyCorrection() async {
    final batchState = ref.read(documentBatchProvider);
    if (_pageIndex == null || _pageIndex! >= batchState.pages.length) return;

    final page = batchState.pages[_pageIndex!];
    if (!page.isLoaded) return;

    final decoded = img.decodeImage(page.imageBytes!);
    if (decoded == null || _corners.length != 4) return;
    final sourceCorners = _corners
        .map((corner) => Offset(
              corner.dx * decoded.width,
              corner.dy * decoded.height,
            ))
        .toList();

    setState(() => _isProcessing = true);

    try {
      final result = await PerspectiveCorrectionService.correct(
        bytes: page.imageBytes!,
        srcPoints: sourceCorners,
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
          correctionCorners: List.from(sourceCorners),
          isCorrectionApplied: true,
          clearFilter: true,
        );

        await ref.read(documentBatchProvider.notifier).updatePageAndPersist(
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
