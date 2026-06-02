import 'package:flutter/material.dart';

import 'document_corners_painter.dart';

class DocumentScannerOverlay extends StatefulWidget {
  const DocumentScannerOverlay({
    super.key,
    this.onAutoCapture,
    this.isAutoCaptureEnabled = true,
    this.autoCaptureDelay = const Duration(milliseconds: 1500),
  });

  final VoidCallback? onAutoCapture;
  final bool isAutoCaptureEnabled;
  final Duration autoCaptureDelay;

  @override
  State<DocumentScannerOverlay> createState() => _DocumentScannerOverlayState();
}

class _DocumentScannerOverlayState extends State<DocumentScannerOverlay> {
  List<Offset> _corners = [];
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _resetCorners();
  }

  void _resetCorners() {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final margin = w * 0.08;
    final topMargin = h * 0.12;

    _corners = [
      Offset(margin, topMargin),
      Offset(w - margin, topMargin),
      Offset(w - margin, h - margin - 80),
      Offset(margin, h - margin - 80),
    ];
  }

  void simulateDocumentDetected() {
    if (!widget.isAutoCaptureEnabled || _isHolding) return;
    _isHolding = true;
    widget.onAutoCapture?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: DocumentCornersPainter(
              corners: _corners,
              showOverlay: true,
            ),
            size: Size.infinite,
          ),
        ),
        if (_isHolding && widget.isAutoCaptureEnabled)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 100,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.amberAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Document detected...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Align document within frame',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
