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

/// Screen allowing users to highlight unwanted objects/text with a red brush
/// and erase them using boundary-propagation auto-heal inpainting.
class MagicRemoveScreen extends StatefulWidget {
  const MagicRemoveScreen({
    super.key,
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  State<MagicRemoveScreen> createState() => _MagicRemoveScreenState();
}

class _MagicRemoveScreenState extends State<MagicRemoveScreen> {
  late Uint8List _currentBytes;
  late Uint8List _originalBytes;
  final List<Uint8List> _history = [];

  final List<Stroke> _strokes = [];
  Stroke? _activeStroke;

  double _brushRadius = 20.0;
  bool _isBusy = false;
  bool _showOriginal = false;

  int? _imgWidth;
  int? _imgHeight;

  double _lastCanvasWidth = 300;
  double _lastCanvasHeight = 400;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
    _originalBytes = widget.imageBytes;
    _decodeDimensions();
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
          _currentBytes = result;
          _strokes.clear();
          _decodeDimensions();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Object erased successfully'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inpainting error: $error'),
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
      backgroundColor: const Color(0xFF111214),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1C1F),
        foregroundColor: Colors.white,
        title: const Text(
          'Magic Remove',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: canUndo && !_isBusy ? _undoStroke : null,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _strokes.isNotEmpty && !_isBusy ? _resetMask : null,
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: 'Reset mask',
          ),
          IconButton(
            onPressed: !_isBusy ? _saveAndExit : null,
            icon: const Icon(Icons.check, color: Color(0xFF2F80ED)),
            tooltip: 'Done',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildCanvas(context),
              ),
            ),
            _buildBottomControls(context),
          ],
        ),
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

            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  _showOriginal ? _originalBytes : _currentBytes,
                  fit: BoxFit.fill,
                ),
                if (!_showOriginal)
                  CustomPaint(
                    painter: _MaskPainter(
                      strokes: _strokes,
                      activeStroke: _activeStroke,
                    ),
                  ),
                if (!_isBusy && !_showOriginal)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      final pos = details.localPosition;
                      if (pos.dx >= 0 &&
                          pos.dx <= constraints.maxWidth &&
                          pos.dy >= 0 &&
                          pos.dy <= constraints.maxHeight) {
                        setState(() {
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
                        });
                      }
                    },
                  ),
                if (_isBusy)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Erasing object...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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
        color: Color(0xFF1B1C1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preset brush sizes & Slider
          Row(
            children: [
              const Text(
                'Brush Size',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: _brushRadius * 0.8,
                height: _brushRadius * 0.8,
                decoration: const BoxDecoration(
                  color: Color(0xCCFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _brushRadius,
                  min: 5.0,
                  max: 60.0,
                  activeColor: const Color(0xFFFF3B30),
                  inactiveColor: Colors.white24,
                  onChanged: (val) => setState(() => _brushRadius = val),
                ),
              ),
            ],
          ),
          // Brush size presets: Small, Medium, Large, Extra Large
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetChip('Small', 10.0),
              _buildPresetChip('Medium', 20.0),
              _buildPresetChip('Large', 35.0),
              _buildPresetChip('X-Large', 50.0),
            ],
          ),
          const SizedBox(height: 14),
          // Action Buttons: Before/After toggle & Erase Object
          Row(
            children: [
              // Before/After Toggle Button
              GestureDetector(
                onTapDown: (_) => setState(() => _showOriginal = true),
                onTapUp: (_) => setState(() => _showOriginal = false),
                onTapCancel: () => setState(() => _showOriginal = false),
                child: OutlinedButton.icon(
                  onPressed: null, // Gesture handler handles press-and-hold
                  icon: Icon(
                    _showOriginal
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: Text(
                    _showOriginal ? 'Showing Original' : 'Hold Before',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Erase Object Action Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _strokes.isNotEmpty && !_isBusy ? _eraseObject : null,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                  label: const Text(
                    'Erase Object',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    disabledBackgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFFFF3B30),
      backgroundColor: Colors.white10,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
      ),
      onSelected: (_) => setState(() => _brushRadius = value),
      visualDensity: VisualDensity.compact,
    );
  }
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

      final paint = Paint()
        ..color = const Color(0x99FF3B30)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.radius * 2;

      if (stroke.points.length == 1) {
        final fillPaint = Paint()
          ..color = const Color(0x99FF3B30)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(stroke.points.first, stroke.radius, fillPaint);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) => true;
}
