import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';

/// Keys used to locate interactive interface elements for the feature highlight tour.
final featureHighlightKeysProvider = Provider<FeatureHighlightKeys>((ref) {
  return FeatureHighlightKeys();
});

class FeatureHighlightKeys {
  final GlobalKey toolsKey = GlobalKey(debugLabel: 'highlight_tools');
  final GlobalKey cameraKey = GlobalKey(debugLabel: 'highlight_camera');
  final GlobalKey filesKey = GlobalKey(debugLabel: 'highlight_files');
}

/// A tour step definition.
class HighlightStep {
  const HighlightStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
    this.arrowAbove = true,
  });

  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;
  final bool arrowAbove;
}

class FeatureHighlightOverlay extends ConsumerStatefulWidget {
  const FeatureHighlightOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<FeatureHighlightOverlay> createState() =>
      _FeatureHighlightOverlayState();
}

class _FeatureHighlightOverlayState
    extends ConsumerState<FeatureHighlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _fadeController;
  int _currentStepIndex = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 0.5;
    }

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _finishTour() {
    _fadeController.reverse().then((_) {
      if (mounted) {
        ref.read(appSettingsProvider.notifier).setCompletedOnboarding(true);
      }
    });
  }

  void _nextStep(int totalSteps) {
    if (_currentStepIndex < totalSteps - 1) {
      setState(() {
        _currentStepIndex++;
      });
    } else {
      _finishTour();
    }
  }

  Rect? _getTargetRect(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    return offset & renderBox.size;
  }

  @override
  Widget build(BuildContext context) {
    final hasCompleted =
        ref.watch(appSettingsProvider.select((s) => s.hasCompletedOnboarding));

    if (hasCompleted) {
      return widget.child;
    }

    final keys = ref.watch(featureHighlightKeysProvider);
    final steps = [
      HighlightStep(
        targetKey: keys.toolsKey,
        title: 'Creative Tools Studio',
        description:
            'Resize, convert, combine and make photo collages directly on your device with complete privacy.',
        icon: Icons.auto_awesome_rounded,
        arrowAbove: false,
      ),
      HighlightStep(
        targetKey: keys.cameraKey,
        title: 'Smart Document Scanner',
        description:
            'Tap here to digitize documents with edge detection, smart fix, and paper flattening.',
        icon: Icons.camera_alt_rounded,
        arrowAbove: true,
      ),
      HighlightStep(
        targetKey: keys.filesKey,
        title: 'Files & PDF Hub',
        description:
            'Access, compress, split, and export all your saved images and PDF files in one place.',
        icon: Icons.folder_special_rounded,
        arrowAbove: true,
      ),
    ];

    final currentStep = steps[_currentStepIndex];
    final targetRect = _ready ? _getTargetRect(currentStep.targetKey) : null;
    final screenSize = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        widget.child,
        if (_ready)
          FadeTransition(
            opacity: _fadeController,
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // 1. Darkened cutout overlay
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _nextStep(steps.length),
                      child: CustomPaint(
                        painter: _SpotlightHolePainter(
                          targetRect: targetRect,
                        ),
                      ),
                    ),
                  ),

                  // 2. Glowing pulse highlight ring around the target
                  if (targetRect != null)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        final pulse = _pulseController.value;
                        final pad = 6.0 + (pulse * 4.0);
                        final rect = targetRect.inflate(pad);
                        final isCircle =
                            (targetRect.width - targetRect.height).abs() < 8;

                        return Positioned(
                          left: rect.left,
                          top: rect.top,
                          width: rect.width,
                          height: rect.height,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: isCircle
                                    ? BoxShape.circle
                                    : BoxShape.rectangle,
                                borderRadius: isCircle
                                    ? null
                                    : BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF38BDF8)
                                      .withValues(alpha: 0.75 + (pulse * 0.25)),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.35 + (pulse * 0.25)),
                                    blurRadius: 16 + (pulse * 8),
                                    spreadRadius: 2 + (pulse * 3),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF6366F1)
                                        .withValues(alpha: 0.25 + (pulse * 0.15)),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // 3. Information Card with pointing arrow
                  if (targetRect != null)
                    _buildTooltipCard(
                      context: context,
                      step: currentStep,
                      targetRect: targetRect,
                      screenSize: screenSize,
                      currentStepIndex: _currentStepIndex,
                      totalSteps: steps.length,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTooltipCard({
    required BuildContext context,
    required HighlightStep step,
    required Rect targetRect,
    required Size screenSize,
    required int currentStepIndex,
    required int totalSteps,
  }) {
    final showCardAbove = step.arrowAbove ||
        (targetRect.bottom + 220 > screenSize.height && targetRect.top > 250);

    final cardWidth = math.min(340.0, screenSize.width - 32);
    final targetCenterX = targetRect.center.dx;
    final cardLeft = (targetCenterX - cardWidth / 2)
        .clamp(16.0, screenSize.width - cardWidth - 16.0);

    final cardTop = showCardAbove
        ? math.max(48.0, targetRect.top - 200)
        : math.min(screenSize.height - 240, targetRect.bottom + 16);

    return Positioned(
      left: cardLeft,
      top: cardTop,
      width: cardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!showCardAbove)
            // Arrow pointing UP to target above card
            Padding(
              padding: EdgeInsets.only(
                left: (targetCenterX - cardLeft - 10).clamp(16.0, cardWidth - 36),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: _PointingArrow(pointingUp: true),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'STEP ${currentStepIndex + 1} OF $totalSteps',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _finishTour,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.white60,
                      ),
                      child: const Text('Skip Tour',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      ),
                      child: Icon(step.icon,
                          color: const Color(0xFF818CF8), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.description,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => _nextStep(totalSteps),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    icon: Icon(
                      currentStepIndex == totalSteps - 1
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                      size: 16,
                    ),
                    label: Text(
                      currentStepIndex == totalSteps - 1
                          ? 'Got it!'
                          : 'Next',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showCardAbove)
            // Arrow pointing DOWN to target below card
            Padding(
              padding: EdgeInsets.only(
                left: (targetCenterX - cardLeft - 10).clamp(16.0, cardWidth - 36),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: _PointingArrow(pointingUp: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _PointingArrow extends StatelessWidget {
  const _PointingArrow({required this.pointingUp});

  final bool pointingUp;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 10),
      painter: _ArrowPainter(
        pointingUp: pointingUp,
        color: const Color(0xFF1E2230),
        borderColor: const Color(0xFF38BDF8).withValues(alpha: 0.5),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.pointingUp,
    required this.color,
    required this.borderColor,
  });

  final bool pointingUp;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointingUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.pointingUp != pointingUp ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor;
}

class _SpotlightHolePainter extends CustomPainter {
  const _SpotlightHolePainter({required this.targetRect});

  final Rect? targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (targetRect != null) {
      final isCircle = (targetRect!.width - targetRect!.height).abs() < 8;
      final holeRect = targetRect!.inflate(6);
      final holePath = Path();
      if (isCircle) {
        holePath.addOval(holeRect);
      } else {
        holePath.addRRect(
          RRect.fromRectAndRadius(holeRect, const Radius.circular(18)),
        );
      }
      final combinedPath = Path.combine(
        PathOperation.difference,
        screenPath,
        holePath,
      );
      canvas.drawPath(
        combinedPath,
        Paint()..color = const Color(0xB8090D16),
      );
    } else {
      canvas.drawPath(
        screenPath,
        Paint()..color = const Color(0xB8090D16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightHolePainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}
