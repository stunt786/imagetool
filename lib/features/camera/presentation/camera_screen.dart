import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/document_batch.dart';
import '../notifiers/document_batch_notifier.dart';
import '../services/document_scanner_service.dart';
import 'widgets/post_capture_menu.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  // Document capture is the primary camera experience. Image capture remains
  // available for users who need a normal photograph.
  bool _isDocumentMode = true;
  bool _isFlashOn = false;
  String? _capturedImagePath;
  bool _isScanningDocument = false;
  int? _previewPageIndex;
  final PageController _previewPageController = PageController();
  bool _hasAutoLaunchedMlKit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    GoRouterState.of(context);
    // Always sync camera lifecycle when dependencies change
    // This handles navigation back from review screen
    _syncCameraLifecycle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _syncCameraLifecycle() {
    try {
      final shell = StatefulNavigationShell.of(context);
      final isCameraTab = shell.currentIndex == 1;

      if (isCameraTab && !_isCameraInitialized) {
        _initializeCamera();
      } else if (!isCameraTab && _isCameraInitialized) {
        _disposeCamera();
      }
    } catch (_) {}
  }

  void _disposeCamera() {
    _controller?.dispose();
    _controller = null;
    _isCameraInitialized = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _isCameraInitialized) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _syncCameraLifecycle();
    }
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        _cameras = await availableCameras();
        if (_cameras.isNotEmpty) {
          await _initCameraController(_cameras[_selectedCameraIndex]);
          // Auto-launch MLKit scanner on first camera init in document mode
          if (mounted && _isDocumentMode && !_hasAutoLaunchedMlKit) {
            _hasAutoLaunchedMlKit = true;
            // Use addPostFrameCallback so the camera preview renders first
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isScanningDocument) {
                _launchMlKitScanner();
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error initializing camera: $e');
      }
    }
  }

  Future<void> _initCameraController(CameraDescription description) async {
    final CameraController cameraController = CameraController(
      description,
      ResolutionPreset.max,
      enableAudio: false,
    );

    _controller = cameraController;

    try {
      await cameraController.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      _isCameraInitialized = false;
      setState(() {});
      _initCameraController(_cameras[_selectedCameraIndex]);
    }
  }

  void _toggleFlash() {
    if (_controller == null) return;
    setState(() => _isFlashOn = !_isFlashOn);
    try {
      _controller!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint('Flash error: $e');
    }
  }

  // ─── Document Scanning (Continuous Multi-Page Capture) ─────────────────

  Future<void> _startNewBatchIfNeeded() async {
    final notifier = ref.read(documentBatchProvider.notifier);
    if (!ref.read(documentBatchProvider).hasPages) {
      await notifier.startNewBatch();
    }
  }

  /// Launch ML Kit document scanner (base mode — no slow filter UI).
  /// Camera is released before ML Kit and re-initialized after to prevent
  /// the frozen preview that occurs when ML Kit is dismissed.
  Future<void> _launchMlKitScanner() async {
    if (_isScanningDocument) return;
    setState(() => _isScanningDocument = true);

    // Release our camera so ML Kit can take over cleanly
    _disposeCamera();

    try {
      final result = await DocumentScannerService.scanDocument();
      if (result != null && result.files.isNotEmpty) {
        await _startNewBatchIfNeeded();
        final notifier = ref.read(documentBatchProvider.notifier);
        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          await notifier.addPageFromPath(file.path);
        }
        if (mounted) {
          final batch = ref.read(documentBatchProvider);
          setState(() {
            _previewPageIndex = batch.pages.length - result.files.length;
          });
          _previewPageController.jumpToPage(_previewPageIndex!);
          HapticFeedback.lightImpact();
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isScanningDocument = false);
        // Always reinitialize camera after ML Kit to avoid frozen preview
        if (_cameras.isNotEmpty) {
          _initCameraController(_cameras[_selectedCameraIndex]);
        }
      }
    }
  }

  // ─── Manual Capture (Image Mode Only) ─────────────────────────────────

  Future<void> _takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (cameraController.value.isTakingPicture) return;

    try {
      final XFile file = await cameraController.takePicture();

      if (mounted) {
        setState(() => _capturedImagePath = file.path);
        _showPostCaptureMenu();
      }
    } on CameraException catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  void _openDocumentReview() {
    context.push('/camera/review');
  }

  Future<void> _discardPreviewPage(int index) async {
    final notifier = ref.read(documentBatchProvider.notifier);
    await notifier.removePage(index);
    if (!mounted) return;
    final batch = ref.read(documentBatchProvider);
    if (!batch.hasPages) {
      setState(() {
        _previewPageIndex = null;
        _isScanningDocument = false;
      });
      _launchMlKitScanner();
    } else {
      final newIndex = index.clamp(0, batch.pages.length - 1);
      setState(
          () => _previewPageIndex = batch.pages.isNotEmpty ? newIndex : null);
    }
  }

  void _cropPreviewPage(int index) {
    context.push('/camera/crop', extra: index);
  }

  void _nextFromPreview() {
    setState(() => _previewPageIndex = null);
    final batch = ref.read(documentBatchProvider);
    if (batch.hasPages) {
      context.push('/camera/review');
    }
  }

  void _addBlankPageToPreview() {
    final batch = ref.read(documentBatchProvider);
    if (batch.pages.isNotEmpty) {
      _previewPageController.animateToPage(
        batch.pages.length,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scanNewPageFromPreview() {
    setState(() => _previewPageIndex = null);
    _launchMlKitScanner();
  }

  Future<void> _removePage(int index) async {
    final notifier = ref.read(documentBatchProvider.notifier);
    await notifier.removePage(index);
    if (mounted) {
      final batch = ref.read(documentBatchProvider);
      if (!batch.hasPages) {
        _launchMlKitScanner();
      }
      setState(() {});
    }
  }

  void _showPostCaptureMenu() {
    if (_capturedImagePath == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PostCaptureMenu(
        imagePath: _capturedImagePath!,
        isDocumentMode: false,
        onRetake: () {
          Navigator.pop(context);
          setState(() => _capturedImagePath = null);
        },
      ),
    ).then((_) {
      if (mounted && _capturedImagePath != null) {
        setState(() => _capturedImagePath = null);
      }
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Ensure camera initializes when build is called and we're on camera tab
    if (!_isCameraInitialized && _controller == null) {
      // Trigger camera initialization on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncCameraLifecycle();
      });
    }

    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final batch = ref.watch(documentBatchProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_capturedImagePath == null && _previewPageIndex == null)
            CameraPreview(_controller!)
          else if (_capturedImagePath != null)
            Image.file(File(_capturedImagePath!), fit: BoxFit.cover),

          // Preview overlay after scan
          if (_previewPageIndex != null && batch.hasPages)
            _buildPreviewOverlay(batch),

          if (_capturedImagePath == null && _previewPageIndex == null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _cameraControl(
                      icon: Icons.close_rounded,
                      onTap: () => context.go('/tools'),
                    ),
                    const Spacer(),
                    const Text(
                      'Scan document',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _cameraControl(
                      icon: _isFlashOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _isFlashOn ? Colors.amberAccent : Colors.white,
                      onTap: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),

          // Controls (hidden during preview)
          if (_capturedImagePath == null && _previewPageIndex == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: 40 + MediaQuery.of(context).padding.bottom,
                  top: 20,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thumbnail strip + Done button
                    if (_isDocumentMode && batch.hasPages)
                      _buildThumbnailStrip(batch, context),

                    if (!_isDocumentMode)
                      _ModeToggle(
                        title: 'Image capture',
                        isSelected: true,
                        onTap: () {},
                      ),

                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (_isDocumentMode) ...[
                          _cameraControl(
                            icon: Icons.photo_library_outlined,
                            onTap: () {},
                          ),
                          GestureDetector(
                            onTap: _isScanningDocument
                                ? null
                                : _launchMlKitScanner,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 4),
                              ),
                              child: Container(
                                margin: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: _isScanningDocument
                                      ? Colors.white54
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: _isScanningDocument
                                    ? const Padding(
                                        padding: EdgeInsets.all(22),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ] else ...[
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.photo_library_rounded,
                                color: Colors.white, size: 28),
                          ),
                          // Shutter button (image mode only)
                          GestureDetector(
                            onTap: _isScanningDocument ? null : _takePicture,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 4),
                              ),
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: _isScanningDocument
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                        _cameraControl(
                          icon: Icons.flip_camera_ios_rounded,
                          onTap: _switchCamera,
                        ),
                      ],
                    ),

                    if (_isDocumentMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          batch.hasPages
                              ? 'Capture another page or tap Done to review'
                              : 'Place the document inside the frame',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
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

  Widget _cameraControl({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 23),
        ),
      ),
    );
  }

  // ─── Preview Overlay ──────────────────────────────────────────────────

  Widget _buildPreviewOverlay(DocumentBatch batch) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            _buildPreviewTopBar(batch),
            Expanded(
              child: PageView.builder(
                controller: _previewPageController,
                itemCount: batch.pages.length + 1,
                onPageChanged: (index) {
                  if (index < batch.pages.length) {
                    setState(() => _previewPageIndex = index);
                  }
                },
                itemBuilder: (context, index) {
                  if (index == batch.pages.length) {
                    return _buildBlankAddPage();
                  }
                  return _buildPreviewPage(index, batch);
                },
              ),
            ),
            _buildPreviewBottomBar(batch),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTopBar(DocumentBatch batch) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _nextFromPreview,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
          const Spacer(),
          Text(
            'Page ${(_previewPageIndex ?? 0) + 1} of ${batch.pageCount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _addBlankPageToPreview,
            icon: const Icon(Icons.add_circle_outline,
                color: Colors.white70, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPage(int index, DocumentBatch batch) {
    final page = batch.pages[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: page.imageBytes != null
            ? Image.memory(
                page.displayBytes,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _previewPlaceholder(),
              )
            : _previewPlaceholder(),
      ),
    );
  }

  Widget _buildBlankAddPage() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.add_rounded, color: Colors.white70, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'Add New Page',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a new document page or import from gallery',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _scanNewPageFromPreview,
            icon: const Icon(Icons.document_scanner_rounded, size: 20),
            label: const Text('Scan New Page'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              backgroundColor: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBottomBar(DocumentBatch batch) {
    final currentIndex = _previewPageIndex ?? 0;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Discard
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _discardPreviewPage(currentIndex),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Discard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                side: BorderSide(
                    color: Colors.red.shade300.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Crop
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _cropPreviewPage(currentIndex),
              icon: const Icon(Icons.crop, size: 18),
              label: const Text('Crop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Next
          Expanded(
            child: FilledButton.icon(
              onPressed: _nextFromPreview,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPlaceholder() {
    return Container(
      color: Colors.grey.shade800,
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white38, size: 48),
      ),
    );
  }

  Widget _buildThumbnailStrip(DocumentBatch batch, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      child: SizedBox(
        height: 80,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: batch.pages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final page = batch.pages[index];
                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: _openDocumentReview,
                        child: Container(
                          width: 56,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: page.imageBytes != null
                              ? Image.memory(
                                  page.displayBytes,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _thumbnailPlaceholder(),
                                )
                              : _thumbnailPlaceholder(),
                        ),
                      ),
                      // Remove button
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removePage(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Page number
                      Positioned(
                        bottom: 2,
                        left: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openDocumentReview,
              icon: const Icon(Icons.check, size: 18),
              label: Text('Done (${batch.pageCount})'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(80, 48),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnailPlaceholder() {
    return Container(
      color: Colors.grey.shade800,
      child: const Icon(Icons.image_outlined, color: Colors.white38, size: 24),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
