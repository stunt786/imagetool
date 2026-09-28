import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shell/presentation/shell_index_scope.dart';
import '../notifiers/document_batch_notifier.dart';
import '../services/document_scanner_service.dart';
import '../services/scanner_capability_service.dart';

final cameraLaunchTriggerProvider = StateProvider<int>((ref) => 0);

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
  bool _isInitializingCamera = false;
  bool _isScanningDocument = false;
  bool _hasAutoLaunchedMlKit = false;

  /// Whether the Google ML Kit document scanner can be used. Probed once per
  /// screen before anything is launched.
  bool _mlScannerAvailable = true;
  bool _capabilityResolved = false;
  bool _capabilityProbeStarted = false;
  bool _isCapturing = false;

  /// Active shell branch index, refreshed on every dependency change.
  int? _shellIndex;
  int? _previousShellIndex;

  /// Branch index of the scanner tab inside the shell.
  static const int _cameraBranchIndex = 1;

  int get _activeShellIndex {
    final scopeIndex = ShellIndexScope.maybeOf(context);
    if (scopeIndex != null) return scopeIndex;
    if (_shellIndex != null) return _shellIndex!;
    try {
      return StatefulNavigationShell.of(context).currentIndex;
    } catch (_) {
      return _cameraBranchIndex;
    }
  }

  /// True when the Google document scanner is the active capture path.
  bool get _useGoogleScanner =>
      resolveCapturePath(
        googleScannerAvailable: _mlScannerAvailable,
        preferBuiltInCamera: false,
      ) ==
      CapturePath.googleScanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resolveCapabilityThenRoute());
  }

  /// Resolves the scanner capability, then routes: the Google scanner when the
  /// device supports it, the built-in camera otherwise.
  ///
  /// The capability is checked *before* the fallback camera starts, so a
  /// supported device never shows (or spends time initialising) the fallback
  /// preview first.
  Future<void> _resolveCapabilityThenRoute() async {
    if (_capabilityProbeStarted) return;
    _capabilityProbeStarted = true;
    final available = await ref
        .read(scannerCapabilityProvider)
        .isGoogleDocumentScannerAvailable();
    if (!mounted) return;
    _capabilityResolved = true;
    setState(() => _mlScannerAvailable = available);
    _syncCameraLifecycle();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newIndex = ShellIndexScope.maybeOf(context) ??
        (() {
          try {
            return StatefulNavigationShell.of(context).currentIndex;
          } catch (_) {
            return null;
          }
        })();

    if (newIndex != null && newIndex != _cameraBranchIndex) {
      _previousShellIndex = newIndex;
    }

    final isEnteringCamera =
        newIndex == _cameraBranchIndex && _shellIndex != _cameraBranchIndex;
    _shellIndex = newIndex;

    // Only reset when initially mounting or entering from another branch
    if (isEnteringCamera) {
      _hasAutoLaunchedMlKit = false;
    }
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
      final isCameraTab = _activeShellIndex == _cameraBranchIndex;

      if (!isCameraTab) {
        _hasAutoLaunchedMlKit = false;
        if (_isCameraInitialized) _disposeCamera();
        return;
      }

      // Resolve the capability first; _resolveCapabilityThenRoute calls back
      // into this method once it knows which path to take.
      if (!_capabilityResolved) {
        unawaited(_resolveCapabilityThenRoute());
        return;
      }

      // Supported device: open the Google scanner straight away and never
      // start the built-in camera.
      if (_useGoogleScanner) {
        if (!_hasAutoLaunchedMlKit && !_isScanningDocument) {
          _hasAutoLaunchedMlKit = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isScanningDocument || !_useGoogleScanner) return;
            if (_activeShellIndex != _cameraBranchIndex) return;
            _launchMlKitScanner();
          });
        }
        return;
      }

      // Built-in camera path: only for unsupported devices.
      if (!_isCameraInitialized && !_isInitializingCamera && !_isScanningDocument) {
        _initializeCamera();
      }
    } catch (_) {}
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    _isCameraInitialized = false;
    if (controller != null) {
      await controller.dispose();
    }
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
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
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
    _isInitializingCamera = false;
    // Re-run routing: on a supported device this is what opens the Google
    // scanner once the fallback preview (if any) is ready.
    if (mounted) _syncCameraLifecycle();
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

  // ─── Document Scanning ──────────────────────────────────────────────────

  Future<void> _startNewBatchIfNeeded() async {
    final notifier = ref.read(documentBatchProvider.notifier);
    if (!ref.read(documentBatchProvider).hasPages) {
      await notifier.startNewBatch();
    }
  }

  Future<void> _launchMlKitScanner() async {
    if (_isScanningDocument) return;
    _hasAutoLaunchedMlKit = true;
    // Safety net: if the Google scanner is not the active path, capture with
    // the built-in camera instead of doing nothing.
    if (!_useGoogleScanner) {
      await _captureWithFallbackCamera();
      return;
    }

    setState(() => _isScanningDocument = true);
    if (_controller != null) {
      await _disposeCamera();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    try {
      final outcome = await DocumentScannerService.scanDocument(
        capability: ref.read(scannerCapabilityProvider),
      );

      if (outcome.isUnavailable) {
        MlKitScannerCapability.markUnavailable();
        if (mounted) {
          setState(() => _mlScannerAvailable = false);
          _showMessage(
            'The Google document scanner is not available on this device. '
            'Using the built-in camera instead.',
          );
        }
        return;
      }

      // Cancelled: the user changed their mind or backed out.
      if (!outcome.isSuccess) {
        if (mounted) {
          _returnToPreviousScreen();
        }
        return;
      }

      await _startNewBatchIfNeeded();
      final notifier = ref.read(documentBatchProvider.notifier);
      for (final file in outcome.files) {
        await notifier.addPageFromPath(file.path);
      }
      if (mounted) {
        HapticFeedback.lightImpact();
        context.push('/camera/review');
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isScanningDocument = false);
        _syncCameraLifecycle();
      }
    }
  }

  /// Fallback capture with the built-in camera.
  ///
  /// Used only when the Google ML Kit scanner is unavailable, so the scanner
  /// tab is never a dead end. The captured page enters the same review,
  /// crop/perspective, filter and PDF pipeline.
  Future<void> _captureWithFallbackCamera() async {
    if (_isCapturing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('The camera is still starting up. Please try again.');
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final shot = await controller.takePicture();
      await _startNewBatchIfNeeded();
      await ref
          .read(documentBatchProvider.notifier)
          .addPageFromPath(shot.path);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      context.push('/camera/review');
    } catch (_) {
      _showMessage('Could not capture the photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(cameraLaunchTriggerProvider, (previous, next) {
      if (next != previous) {
        _hasAutoLaunchedMlKit = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _useGoogleScanner && !_isScanningDocument) {
            _launchMlKitScanner();
          }
        });
      }
    });

    if (!_isCameraInitialized && _controller == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncCameraLifecycle();
      });
    }

    final child = _useGoogleScanner
        ? _buildGoogleScannerView()
        : (!_isCameraInitialized || _controller == null)
            ? const Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildFallbackCameraView();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _returnToPreviousScreen();
      },
      child: child,
    );
  }

  void _returnToPreviousScreen() {
    _hasAutoLaunchedMlKit = false;
    try {
      final shell = StatefulNavigationShell.of(context);
      shell.goBranch(_previousShellIndex ?? 0, initialLocation: true);
    } catch (_) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tools');
      }
    }
  }

  void _handleClose() {
    _returnToPreviousScreen();
  }

  Widget _buildGoogleScannerView() {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(),
    );
  }

  Widget _buildFallbackCameraView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          // Scan guide overlay
          const Center(
            child: _ScanGuideOverlay(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _cameraControl(
                    icon: Icons.close_rounded,
                    onTap: _handleClose,
                  ),
                  const Spacer(),
                  const Text(
                    'Scan Document',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _cameraControl(
                    icon: Icons.flip_camera_ios_rounded,
                    onTap: _switchCamera,
                  ),
                ],
              ),
            ),
          ),
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
                  GestureDetector(
                    onTap: (_isScanningDocument || _isCapturing)
                        ? null
                        : _captureWithFallbackCamera,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: (_isScanningDocument || _isCapturing)
                            ? const Padding(
                                padding: EdgeInsets.all(22),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.black,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Built-in camera',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
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
}

class _ScanGuideOverlay extends StatelessWidget {
  const _ScanGuideOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size(
          MediaQuery.sizeOf(context).width * 0.75,
          MediaQuery.sizeOf(context).height * 0.55,
        ),
        painter: _ScanGuidePainter(),
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 8.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(Offset(r, 0), Offset(cornerLen, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, cornerLen), paint);
    canvas.drawArc(const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 3.14159 / 2, false, paint);

    // Top-right
    canvas.drawLine(Offset(w - cornerLen, 0), Offset(w - r, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, cornerLen), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), -3.14159 / 2, -3.14159 / 2, false, paint);

    // Bottom-left
    canvas.drawLine(Offset(0, h - cornerLen), Offset(0, h - r), paint);
    canvas.drawLine(Offset(r, h), Offset(cornerLen, h), paint);
    canvas.drawArc(Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), 3.14159 / 2, 3.14159 / 2, false, paint);

    // Bottom-right
    canvas.drawLine(Offset(w, h - cornerLen), Offset(w, h - r), paint);
    canvas.drawLine(Offset(w - cornerLen, h), Offset(w - r, h), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), 0, 3.14159 / 2, false, paint);
  }

  @override
  bool shouldRepaint(_ScanGuidePainter oldDelegate) => false;
}
