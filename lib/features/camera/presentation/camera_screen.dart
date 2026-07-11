import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../notifiers/document_batch_notifier.dart';
import '../services/document_scanner_service.dart';
import '../services/perspective_correction_service.dart';
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

  // ─── Document Scanning (Android: ML Kit, iOS: Manual Fallback) ──────────

  Future<void> _startDocumentScan() async {
    if (_isScanningDocument) return;
    setState(() => _isScanningDocument = true);

    try {
      // Try ML Kit document scanner first
      final result = await DocumentScannerService.scanDocument();

      if (result != null && result.files.isNotEmpty) {
        await _addScannedFiles(result.files);
      } else {
        // ML Kit failed (iOS or unavailable) — use manual camera capture
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Scanner unavailable, using manual capture'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {
      // Fallback: manual capture in document mode
    } finally {
      if (mounted) {
        setState(() => _isScanningDocument = false);
      }
    }
  }

  Future<void> _addScannedFiles(List<File> files) async {
    final notifier = ref.read(documentBatchProvider.notifier);
    if (!ref.read(documentBatchProvider).hasPages) {
      await notifier.startNewBatch();
    }

    for (final file in files) {
      await notifier.addPageFromPath(file.path);
    }

    if (mounted) {
      setState(() {
        _batchPageCount = ref.read(documentBatchProvider).pageCount;
      });

      // Navigate to review with the scanned pages
      context.push('/camera/review');
    }
  }

  // ─── Manual Capture (Image Mode + iOS Fallback) ─────────────────────────

  Future<void> _takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (cameraController.value.isTakingPicture) return;

    try {
      final XFile file = await cameraController.takePicture();

      if (_isDocumentMode) {
        await _addDocumentPage(file);
      } else {
        if (mounted) {
          setState(() => _capturedImagePath = file.path);
          _showPostCaptureMenu();
        }
      }
    } on CameraException catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _addDocumentPage(XFile file) async {
    final fileBytes = await File(file.path).readAsBytes();
    Uint8List finalBytes = fileBytes;

    // Post-capture auto-correction: detect document and straighten
    try {
      final corrected = await _autoCorrectDocument(fileBytes);
      if (corrected != null) {
        finalBytes = corrected;
      }
    } catch (_) {}

    // Save corrected image to temp location
    final tempDir = Directory('${await _tempDirPath()}');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final correctedPath =
        '${tempDir.path}/doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(correctedPath).writeAsBytes(finalBytes);

    final notifier = ref.read(documentBatchProvider.notifier);
    if (!ref.read(documentBatchProvider).hasPages) {
      await notifier.startNewBatch();
    }
    await notifier.addPageFromPath(correctedPath);

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
  }

  /// Post-capture document auto-correction.
  /// Detects document edges in the captured image and straightens perspective.
  Future<Uint8List?> _autoCorrectDocument(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final width = decoded.width;
    final height = decoded.height;

    // Downscale for detection speed
    final scale = 600.0 / width;
    final smallW = (width * scale).round().clamp(200, 800);
    final smallH = (height * scale).round().clamp(200, 800);
    final small = img.copyResize(decoded, width: smallW, height: smallH);

    // Find document corners in downscaled image
    final corners = _detectDocumentCorners(small);
    if (corners == null) return null;

    // Map corners back to original image coordinates
    final pixelCorners = corners
        .map((c) => Offset(
              c.dx / scale,
              c.dy / scale,
            ))
        .toList();

    // Apply perspective correction
    final corrected = await PerspectiveCorrectionService.correct(
      bytes: bytes,
      srcPoints: pixelCorners,
      targetWidth: width,
      targetHeight: height,
    );

    return corrected?.bytes;
  }

  /// Detect document edges in a downscaled grayscale image using line scanning.
  List<Offset>? _detectDocumentCorners(img.Image image) {
    final gray = img.grayscale(image);
    final blurred = img.gaussianBlur(gray, radius: 3);
    final w = blurred.width;
    final h = blurred.height;

    // Edge detection (Sobel)
    final edges = img.Image(width: w, height: h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = blurred.getPixel(x + 1, y - 1).r.toInt() +
            2 * blurred.getPixel(x + 1, y).r.toInt() +
            blurred.getPixel(x + 1, y + 1).r.toInt() -
            blurred.getPixel(x - 1, y - 1).r.toInt() -
            2 * blurred.getPixel(x - 1, y).r.toInt() -
            blurred.getPixel(x - 1, y + 1).r.toInt();
        final gy = blurred.getPixel(x - 1, y + 1).r.toInt() +
            2 * blurred.getPixel(x, y + 1).r.toInt() +
            blurred.getPixel(x + 1, y + 1).r.toInt() -
            blurred.getPixel(x - 1, y - 1).r.toInt() -
            2 * blurred.getPixel(x, y - 1).r.toInt() -
            blurred.getPixel(x + 1, y - 1).r.toInt();
        final mag = (gx * gx + gy * gy) > 2500 ? 255 : 0;
        edges.setPixelRgba(x, y, mag, mag, mag, 255);
      }
    }

    // Collect edge points from each side
    final step = math.max(1, math.min(w, h) ~/ 60);
    final topPts = <Offset>[];
    final bottomPts = <Offset>[];
    final leftPts = <Offset>[];
    final rightPts = <Offset>[];

    for (var x = step; x < w - step; x += step) {
      for (var y = 1; y < h - 1; y++) {
        if (edges.getPixel(x, y).r > 128) {
          topPts.add(Offset(x.toDouble(), y.toDouble()));
          break;
        }
      }
      for (var y = h - 2; y > 0; y--) {
        if (edges.getPixel(x, y).r > 128) {
          bottomPts.add(Offset(x.toDouble(), y.toDouble()));
          break;
        }
      }
    }

    for (var y = step; y < h - step; y += step) {
      for (var x = 1; x < w - 1; x++) {
        if (edges.getPixel(x, y).r > 128) {
          leftPts.add(Offset(x.toDouble(), y.toDouble()));
          break;
        }
      }
      for (var x = w - 2; x > 0; x--) {
        if (edges.getPixel(x, y).r > 128) {
          rightPts.add(Offset(x.toDouble(), y.toDouble()));
          break;
        }
      }
    }

    if (topPts.length < 5 || bottomPts.length < 5 ||
        leftPts.length < 5 || rightPts.length < 5) {
      return null;
    }

    // Fit lines and find intersections
    final topLine = _fitLine(topPts);
    final bottomLine = _fitLine(bottomPts);
    final leftLine = _fitLine(leftPts);
    final rightLine = _fitLine(rightPts);

    if (topLine == null || bottomLine == null ||
        leftLine == null || rightLine == null) {
      return null;
    }

    final tl = _intersect(leftLine, topLine);
    final tr = _intersect(rightLine, topLine);
    final br = _intersect(rightLine, bottomLine);
    final bl = _intersect(leftLine, bottomLine);

    if (tl == null || tr == null || br == null || bl == null) return null;

    final margin = 4.0;
    final corners = [
      Offset(tl.dx.clamp(margin, w - margin), tl.dy.clamp(margin, h - margin)),
      Offset(tr.dx.clamp(0, w - margin), tr.dy.clamp(margin, h - margin)),
      Offset(br.dx.clamp(0, w - margin), br.dy.clamp(0, h - margin)),
      Offset(bl.dx.clamp(margin, w - margin), bl.dy.clamp(0, h - margin)),
    ];

    // Validate area
    final area = _quadArea(corners);
    if (area < w * h * 0.03 || area > w * h * 0.97) return null;

    return corners;
  }

  List<double>? _fitLine(List<Offset> pts) {
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final p in pts) {
      sx += p.dx; sy += p.dy; sxx += p.dx * p.dx; sxy += p.dx * p.dy;
    }
    final n = pts.length.toDouble();
    final d = n * sxx - sx * sx;
    if (d.abs() < 1e-10) return null;
    final m = (n * sxy - sx * sy) / d;
    final b = (sy - m * sx) / n;
    return [m, b];
  }

  Offset? _intersect(List<double> a, List<double> b) {
    if ((a[0] - b[0]).abs() < 1e-8) return null;
    final x = (b[1] - a[1]) / (a[0] - b[0]);
    final y = a[0] * x + a[1];
    return Offset(x, y);
  }

  double _quadArea(List<Offset> pts) {
    var a = 0.0;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      a += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
    }
    return a.abs() / 2;
  }

  Future<String> _tempDirPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/doc_captures';
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
      // Launch ML Kit document scanner for a CamScanner-like experience
      _startDocumentScan();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

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

          // Document mode overlay (static frame guide)
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
                                color:
                                    Colors.amberAccent.withValues(alpha: 0.3),
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
                          _batchPageCount > 0
                              ? 'Tap to add another page'
                              : 'Launching scanner...',
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
