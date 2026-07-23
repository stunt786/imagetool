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
import 'widgets/document_scanner_overlay.dart';
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
  bool _isDocumentMode = false;
  bool _isFlashOn = false;
  String? _capturedImagePath;
  bool _isScanningDocument = false;

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
          setState(() {});
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

  Future<void> _removePage(int index) async {
    final notifier = ref.read(documentBatchProvider.notifier);
    await notifier.removePage(index);
    if (mounted) setState(() {});
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

  void _onModeChanged(bool isDocumentMode) {
    setState(() => _isDocumentMode = isDocumentMode);

    if (_isDocumentMode) {
      _startNewBatchIfNeeded();
      // Auto-launch ML Kit scanner as the auto scan mode on first entry
      if (!ref.read(documentBatchProvider).hasPages) {
        _launchMlKitScanner();
      }
    }
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
          if (_capturedImagePath == null)
            CameraPreview(_controller!)
          else
            Image.file(File(_capturedImagePath!), fit: BoxFit.cover),

          // Document mode overlay (only show when no pages scanned yet)
          if (_capturedImagePath == null && _isDocumentMode && !batch.hasPages)
            const IgnorePointer(
              child: DocumentScannerOverlay(),
            ),

          // Controls
          if (_capturedImagePath == null)
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

                    // Mode Toggle
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeToggle(
                            title: 'Image',
                            isSelected: !_isDocumentMode,
                            onTap: () => _onModeChanged(false),
                          ),
                          _ModeToggle(
                            title: 'Document',
                            isSelected: _isDocumentMode,
                            onTap: () => _onModeChanged(true),
                          ),
                        ],
                      ),
                    ),

                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (_isDocumentMode) ...[
                          // ML Kit Smart Scan (document mode only)
                          IconButton(
                            onPressed: _isScanningDocument
                                ? null
                                : _launchMlKitScanner,
                            icon: _isScanningDocument
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                : const Icon(
                                    Icons.document_scanner_rounded,
                                    color: Colors.white,
                                    size: 28,
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
                                border: Border.all(
                                    color: Colors.white, width: 4),
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
                        IconButton(
                          onPressed: _toggleFlash,
                          icon: Icon(
                            _isFlashOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            color: _isFlashOn
                                ? Colors.amberAccent
                                : Colors.white,
                            size: 28,
                          ),
                        ),
                        IconButton(
                          onPressed: _switchCamera,
                          icon: const Icon(Icons.flip_camera_ios_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ],
                    ),

                    if (_isDocumentMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          batch.hasPages
                              ? 'Tap thumbnail to finish · Tap scanner to add more'
                              : 'Tap scanner to capture document pages',
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
