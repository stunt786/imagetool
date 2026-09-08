import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/magic_remove_service.dart';

/// Represents a single brush stroke drawn on the canvas.
class Stroke {
  Stroke({required this.points, required this.radius});

  final List<Offset> points;
  final double radius;
}

/// Professional magic remove screen with edge-aware inpainting,
/// real-time brush cursor, and before/after comparison.
class MagicRemoveScreen extends StatefulWidget {
  const MagicRemoveScreen({
    super.key,
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  State<MagicRemoveScreen> createState() => _MagicRemoveScreenState();
}

class _MagicRemoveScreenState extends State<MagicRemoveScreen>
    with SingleTickerProviderStateMixin {
  late Uint8List _currentBytes;
  late Uint8List _originalBytes;
  static const int _maxHistory = 5;
  final List<Uint8List> _history = [];

  final List<Stroke> _strokes = [];
  Stroke? _activeStroke;

  double _brushRadius = 20.0;
  bool _isBusy = false;
  bool _showComparison = false;
  double _comparisonPosition = 0.5;

  int? _imgWidth;
  int? _imgHeight;

  double _lastCanvasWidth = 300;
  double _lastCanvasHeight = 400;

  Offset? _pointerPosition;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
    _originalBytes = widget.imageBytes;
    _decodeDimensions();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _decodeDimensions() {
    final decoded = img.decodeImage(_currentBytes);
    if (decoded != null) {
      _imgWidth = decoded.width;
      _imgHeight = decoded.height;
    }
  }

  void _undoStroke() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    } else if (_history.isNotEmpty) {
      setState(() {
        _currentBytes = _history.removeLast();
        _decodeDimensions();
      });
    }
  }

  void _resetMask() {
    setState(() {
      _strokes.clear();
      _activeStroke = null;
    });
  }

  void _saveAndExit() {
    Navigator.pop(context, _currentBytes);
  }

  Future<void> _eraseObject() async {
    if (_strokes.isEmpty || _isBusy) return;
    setState(() => _isBusy = true);

    try {
      final allPoints = <Offset>[];
      for (final stroke in _strokes) {
        allPoints.addAll(stroke.points);
      }

      final result = await MagicRemoveService.inpaintObject(
        imageBytes: _currentBytes,
        points: allPoints,
        brushRadius: _brushRadius,
        imageWidth: _lastCanvasWidth,
        imageHeight: _lastCanvasHeight,
      );

      if (result != null && mounted) {
        setState(() {
          _history.add(_currentBytes);
          if (_history.length > _maxHistory) {
            _history.removeAt(0);
          }
          _currentBytes = result;
          _strokes.clear();
          _decodeDimensions();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Object erased'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = _strokes.isNotEmpty || _history.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(canUndo),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _buildCanvas(context),
              ),
            ),
            _buildBottomControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool canUndo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF16171A),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
            tooltip: 'Cancel',
          ),
          const Expanded(
            child: Text(
              'Magic Remove',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: canUndo && !_isBusy ? _undoStroke : null,
            icon: Icon(
              Icons.undo,
              color: canUndo ? Colors.white70 : Colors.white24,
              size: 22,
            ),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: !_isBusy ? _saveAndExit : null,
            icon: Icon(
              Icons.check_circle,
              color: !_isBusy ? const Color(0xFF34C759) : Colors.white24,
              size: 26,
            ),
            tooltip: 'Done',
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    if (_imgWidth == null || _imgHeight == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final aspectRatio = _imgWidth! / _imgHeight!;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _lastCanvasWidth = constraints.maxWidth;
            _lastCanvasHeight = constraints.maxHeight;

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Main image
                  Image.memory(
                    _currentBytes,
                    fit: BoxFit.fill,
                  ),

                  // Comparison: original image with clip
                  if (_showComparison)
                    ClipRect(
                      clipper: _ComparisonClipper(_comparisonPosition),
                      child: Image.memory(
                        _originalBytes,
                        fit: BoxFit.fill,
                      ),
                    ),

                  // Comparison divider line
                  if (_showComparison)
                    Positioned(
                      left: _comparisonPosition * constraints.maxWidth - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white,
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Comparison handle
                  if (_showComparison)
                    Positioned(
                      left: _comparisonPosition * constraints.maxWidth - 16,
                      top: constraints.maxHeight / 2 - 16,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.swap_horiz,
                          size: 18,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                  // Stroke overlay
                  if (!_showComparison && !_isBusy)
                    CustomPaint(
                      painter: _MaskPainter(
                        strokes: _strokes,
                        activeStroke: _activeStroke,
                      ),
                      size: Size.infinite,
                    ),

                  // Brush cursor follower
                  if (!_showComparison && !_isBusy && _pointerPosition != null)
                    Positioned(
                      left: _pointerPosition!.dx - _brushRadius,
                      top: _pointerPosition!.dy - _brushRadius,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Container(
                              width: _brushRadius * 2,
                              height: _brushRadius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: _pulseAnimation.value * 0.7,
                                  ),
                                  width: 1.5,
                                ),
                                color: const Color(0x22FF3B30),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // Gesture detector
                  if (!_showComparison && !_isBusy)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (details) {
                        final pos = details.localPosition;
                        if (pos.dx >= 0 &&
                            pos.dx <= constraints.maxWidth &&
                            pos.dy >= 0 &&
                            pos.dy <= constraints.maxHeight) {
                          setState(() {
                            _pointerPosition = pos;
                            _activeStroke = Stroke(
                              points: [pos],
                              radius: _brushRadius,
                            );
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        final pos = details.localPosition;
                        if (pos.dx >= 0 &&
                            pos.dx <= constraints.maxWidth &&
                            pos.dy >= 0 &&
                            pos.dy <= constraints.maxHeight) {
                          setState(() {
                            _pointerPosition = pos;
                            _activeStroke?.points.add(pos);
                          });
                        }
                      },
                      onPanEnd: (details) {
                        if (_activeStroke != null &&
                            _activeStroke!.points.isNotEmpty) {
                          setState(() {
                            _strokes.add(_activeStroke!);
                            _activeStroke = null;
                            _pointerPosition = null;
                          });
                        }
                      },
                      onPanCancel: () {
                        setState(() {
                          _pointerPosition = null;
                        });
                      },
                    ),

                  // Processing overlay
                  if (_isBusy)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _ProcessingIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Analyzing and removing...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Using edge-aware inpainting',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Stroke count badge
                  if (_strokes.isNotEmpty && !_isBusy && !_showComparison)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_strokes.length} stroke${_strokes.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF16171A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Comparison toggle
          Row(
            children: [
              Icon(
                _showComparison ? Icons.compare : Icons.visibility_off_outlined,
                color: Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _showComparison ? 'Drag to compare' : 'Hold to compare with original',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
              GestureDetector(
                onTapDown: (_) => setState(() => _showComparison = true),
                onTapUp: (_) => setState(() => _showComparison = false),
                onTapCancel: () => setState(() => _showComparison = false),
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _comparisonPosition = (details.localPosition.dx /
                            context.size!.width)
                        .clamp(0.05, 0.95);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showComparison
                        ? const Color(0xFF2F80ED)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _showComparison ? 'Comparing' : 'Compare',
                    style: TextStyle(
                      color: _showComparison ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Brush size
          Row(
            children: [
              const Text(
                'Brush',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: math.max(_brushRadius * 0.7, 8),
                height: math.max(_brushRadius * 0.7, 8),
                decoration: const BoxDecoration(
                  color: Color(0xCCFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFFF3B30),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFFFF3B30),
                    overlayColor: const Color(0x22FF3B30),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: _brushRadius,
                    min: 5.0,
                    max: 60.0,
                    onChanged: (val) => setState(() => _brushRadius = val),
                  ),
                ),
              ),
            ],
          ),

          // Preset sizes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetChip('S', 10.0),
              _buildPresetChip('M', 20.0),
              _buildPresetChip('L', 35.0),
              _buildPresetChip('XL', 50.0),
            ],
          ),
          const SizedBox(height: 14),

          // Action row
          Row(
            children: [
              if (_strokes.isNotEmpty && !_isBusy)
                GestureDetector(
                  onTap: _resetMask,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cleaning_services_outlined, color: Colors.white70, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Clear',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_strokes.isNotEmpty && !_isBusy) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _strokes.isNotEmpty && !_isBusy ? _eraseObject : null,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                  label: Text(
                    _strokes.isEmpty ? 'Draw to select' : 'Erase (${_strokes.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white30,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double value) {
    final isSelected = (_brushRadius - value).abs() < 4.0;
    return GestureDetector(
      onTap: () => setState(() => _brushRadius = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF3B30) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Clipper that reveals the original image up to a horizontal position.
class _ComparisonClipper extends CustomClipper<Rect> {
  _ComparisonClipper(this.position);

  final double position;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * position, size.height);
  }

  @override
  bool shouldReclip(covariant _ComparisonClipper oldClipper) {
    return oldClipper.position != position;
  }
}

/// Animated pulsing processing indicator.
class _ProcessingIndicator extends StatefulWidget {
  const _ProcessingIndicator();

  @override
  State<_ProcessingIndicator> createState() => _ProcessingIndicatorState();
}

class _ProcessingIndicatorState extends State<_ProcessingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(48, 48),
          painter: _ProcessingPainter(_controller.value),
        );
      },
    );
  }
}

class _ProcessingPainter extends CustomPainter {
  _ProcessingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background circle
    final bgPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    // Animated arc
    final arcPaint = Paint()
      ..color = const Color(0xFFFF3B30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final startAngle = 2 * math.pi * progress - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      math.pi * 1.2,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProcessingPainter oldDelegate) => true;
}

class _MaskPainter extends CustomPainter {
  _MaskPainter({required this.strokes, required this.activeStroke});

  final List<Stroke> strokes;
  final Stroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final allStrokes = [...strokes];
    if (activeStroke != null) allStrokes.add(activeStroke!);

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) continue;

      // Glow effect
      final glowPaint = Paint()
        ..color = const Color(0x33FF3B30)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.radius * 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      // Main stroke
      final paint = Paint()
        ..color = const Color(0x88FF3B30)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.radius * 2;

      if (stroke.points.length == 1) {
        final fillPaint = Paint()
          ..color = const Color(0x44FF3B30)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(stroke.points.first, stroke.radius, fillPaint);
        canvas.drawCircle(stroke.points.first, stroke.radius, paint);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) => true;
}
