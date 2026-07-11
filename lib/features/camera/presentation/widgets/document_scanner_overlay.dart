import 'package:flutter/material.dart';

import 'document_corners_painter.dart';

class DocumentScannerOverlay extends StatelessWidget {
  const DocumentScannerOverlay({
    super.key,
    this.detectedCorners,
    this.isDocumentDetected = false,
    this.autoCaptureProgress,
    this.isAutoCaptureEnabled = true,
    this.onAutoCapture,
  });

  final List<Offset>? detectedCorners;
  final bool isDocumentDetected;
  final double? autoCaptureProgress;
  final bool isAutoCaptureEnabled;
  final VoidCallback? onAutoCapture;

  List<Offset> _defaultCorners(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final margin = w * 0.08;
    final topMargin = h * 0.12;

    return [
      Offset(margin, topMargin),
      Offset(w - margin, topMargin),
      Offset(w - margin, h - margin - 80),
      Offset(margin, h - margin - 80),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final corners = detectedCorners ?? _defaultCorners(context);
    final showCapturing = isDocumentDetected && isAutoCaptureEnabled;

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: DocumentCornersPainter(
              corners: corners,
              showOverlay: true,
              cornerColor: isDocumentDetected
                  ? Colors.greenAccent
                  : Colors.amberAccent,
            ),
            size: Size.infinite,
          ),
        ),
        // Top instruction banner
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + 16,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDocumentDetected
                    ? Colors.green.withValues(alpha: 0.7)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDocumentDetected
                        ? Icons.check_circle_outline
                        : Icons.document_scanner_outlined,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDocumentDetected
                        ? 'Document detected'
                        : 'Align document within frame',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Auto-capture countdown ring
        if (showCapturing && autoCaptureProgress != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 160,
            child: Center(
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        value: autoCaptureProgress,
                        strokeWidth: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.greenAccent,
                        ),
                      ),
                    ),
                    Text(
                      '${((1.0 - (autoCaptureProgress ?? 0)) * 1.5).round()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
