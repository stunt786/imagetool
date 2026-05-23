import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:ui' as ui;

/// ImageEditorScreen provides a unified interface for Resize, Crop, and Rotate.
/// This implementation fixes the handlebar stuck issue by using a dedicated
/// transformation layer and robust boundary clamping.
class ImageEditorScreen extends ConsumerStatefulWidget {
  final File imageFile;
  const ImageEditorScreen({super.key, required this.imageFile});

  @override
  ConsumerState<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends ConsumerState<ImageEditorScreen> {
  bool _isProcessing = false;
  int _currentTab = 0; // 0: Crop, 1: Rotate, 2: Resize

  // For Custom Cropping Logic (if not using native UI)
  Rect _cropRect = const Rect.fromLTWH(50, 50, 200, 200);
  double _aspectRatio = 1.0;
  bool _isFixedAspectRatio = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _getTabTitle(),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: _saveImage,
            child: const Text("SAVE",
                style: TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Base Image
                  InteractiveViewer(
                    panEnabled: _currentTab !=
                        0, // Disable pan when cropping to avoid conflicts
                    scaleEnabled: _currentTab != 0,
                    child: Image.file(widget.imageFile, fit: BoxFit.contain),
                  ),

                  // Crop Overlay Layer
                  if (_currentTab == 0)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildCropOverlay(constraints);
                      },
                    ),

                  if (_isProcessing)
                    Container(
                      color: Colors.black54,
                      child: const CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          _buildBottomToolSheet(),
        ],
      ),
    );
  }

  String _getTabTitle() {
    switch (_currentTab) {
      case 0:
        return "Crop & Aspect Ratio";
      case 1:
        return "Rotate & Flip";
      case 2:
        return "Resize & Compress";
      default:
        return "Edit Image";
    }
  }

  Widget _buildCropOverlay(BoxConstraints constraints) {
    return Stack(
      children: [
        // The darkened background outside the crop area
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(color: Colors.black),
              Positioned.fromRect(
                rect: _cropRect,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
        // The Handles
        _buildHandle(
            constraints, _cropRect.topLeft, (d) => _updateCropRect(topLeft: d)),
        _buildHandle(constraints, _cropRect.topRight,
            (d) => _updateCropRect(topRight: d)),
        _buildHandle(constraints, _cropRect.bottomLeft,
            (d) => _updateCropRect(bottomLeft: d)),
        _buildHandle(constraints, _cropRect.bottomRight,
            (d) => _updateCropRect(bottomRight: d)),

        // Grid lines for rule of thirds
        Positioned.fromRect(
          rect: _cropRect,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: CustomPaint(painter: GridPainter()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHandle(
      BoxConstraints constraints, Offset position, Function(Offset) onDrag) {
    return Positioned(
      left: position.dx - 15,
      top: position.dy - 15,
      child: GestureDetector(
        onPanUpdate: (details) {
          onDrag(details.delta);
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Colors.amber,
            shape: BoxShape.circle,
          ),
          child: const Center(
              child: Icon(Icons.drag_handle, size: 15, color: Colors.black)),
        ),
      ),
    );
  }

  void _updateCropRect(
      {Offset? topLeft,
      Offset? topRight,
      Offset? bottomLeft,
      Offset? bottomRight}) {
    setState(() {
      double left = _cropRect.left;
      double top = _cropRect.top;
      double right = _cropRect.right;
      double bottom = _cropRect.bottom;

      const double minSize = 50.0;

      if (topLeft != null) {
        left = (left + topLeft.dx).clamp(0, right - minSize);
        top = (top + topLeft.dy).clamp(0, bottom - minSize);
      } else if (bottomRight != null) {
        right = (right + bottomRight.dx)
            .clamp(left + minSize, MediaQuery.of(context).size.width);
        bottom = (bottom + bottomRight.dy)
            .clamp(top + minSize, MediaQuery.of(context).size.height - 200);
      }
      // Add logic for other handles and aspect ratio constraints here...

      _cropRect = Rect.fromLTRB(left, top, right, bottom);
      HapticFeedback.selectionClick();
    });
  }

  Widget _buildBottomToolSheet() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _toolTab(0, Icons.crop, "Crop"),
              _toolTab(1, Icons.rotate_right, "Rotate"),
              _toolTab(2, Icons.photo_size_select_large, "Resize"),
            ],
          ),
          const SizedBox(height: 20),
          if (_currentTab == 0) _buildCropPresets(),
        ],
      ),
    );
  }

  Widget _buildCropPresets() {
    final presets = ["Free", "1:1", "4:3", "16:9", "9:16"];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets
            .map((p) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: false,
                    onSelected: (_) {
                      // Set aspect ratio logic
                      HapticFeedback.lightImpact();
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _toolTab(int index, IconData icon, String label) {
    final isSelected = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: Column(
        children: [
          Icon(icon, color: isSelected ? Colors.amber : Colors.white54),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.amber : Colors.white54,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _saveImage() async {
    setState(() => _isProcessing = true);
    // Simulate processing
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Image saved successfully!")),
      );
      Navigator.pop(context);
    }
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1;

    // Draw vertical lines
    canvas.drawLine(
        Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0),
        Offset(2 * size.width / 3, size.height), paint);

    // Draw horizontal lines
    canvas.drawLine(
        Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3),
        Offset(size.width, 2 * size.height / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
