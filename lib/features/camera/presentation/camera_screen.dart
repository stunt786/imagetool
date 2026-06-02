import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../notifiers/document_batch_notifier.dart';
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
  int _batchPageCount = 0;
  bool _wasCameraTab = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    GoRouterState.of(context);
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

      if (isCameraTab == _wasCameraTab) return;
      _wasCameraTab = isCameraTab;

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
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.jpeg,
    );

    _controller = cameraController;

    try {
      await cameraController.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
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

  Future<void> _takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (cameraController.value.isTakingPicture) {
      return;
    }

    try {
      final XFile file = await cameraController.takePicture();

      if (_isDocumentMode) {
        final notifier = ref.read(documentBatchProvider.notifier);
        if (!ref.read(documentBatchProvider).hasPages) {
          notifier.startNewBatch();
        }
        await notifier.addPageFromPath(file.path);
        if (mounted) {
          setState(() {
            _batchPageCount = ref.read(documentBatchProvider).pageCount;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Page ${_batchPageCount} captured'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
              action: SnackBarAction(
                label: 'Review',
                onPressed: () => _openDocumentReview(),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _capturedImagePath = file.path;
          });
          _showPostCaptureMenu();
        }
      }
    } on CameraException catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  void _openDocumentReview() {
    context.push('/camera/review');
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
          setState(() {
            _capturedImagePath = null;
          });
        },
      ),
    ).then((_) {
      if (mounted && _capturedImagePath != null) {
        setState(() {
          _capturedImagePath = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_capturedImagePath == null)
            CameraPreview(_controller!)
          else
            Image.file(File(_capturedImagePath!), fit: BoxFit.cover),

          // Document mode overlay (purely visual, IgnorePointer prevents blocking controls)
          if (_capturedImagePath == null && _isDocumentMode)
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
                            onTap: () =>
                                setState(() => _isDocumentMode = false),
                          ),
                          _ModeToggle(
                            title: 'Document',
                            isSelected: _isDocumentMode,
                            onTap: () =>
                                setState(() => _isDocumentMode = true),
                          ),
                        ],
                      ),
                    ),

                    // Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.photo_library_rounded,
                              color: Colors.white, size: 28),
                        ),
                        if (_isDocumentMode && _batchPageCount > 0)
                          GestureDetector(
                            onTap: _openDocumentReview,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.amberAccent
                                        .withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.description,
                                      color: Colors.amberAccent, size: 18),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_batchPageCount',
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: _takePicture,
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
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleFlash,
                          icon: Icon(
                            _isFlashOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            color: _isFlashOn ? Colors.amberAccent : Colors.white,
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
                          _batchPageCount > 0
                              ? 'Tap to add another page'
                              : 'Frame document and capture',
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
