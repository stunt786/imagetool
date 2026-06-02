import 'package:flutter/material.dart';

class DocumentCornersPainter extends CustomPainter {
  DocumentCornersPainter({
    required this.corners,
    this.cornerRadius = 16,
    this.strokeWidth = 3,
    this.cornerColor,
    this.overlayColor,
    this.showOverlay = true,
  });

  final List<Offset> corners;
  final double cornerRadius;
  final double strokeWidth;
  final Color? cornerColor;
  final Color? overlayColor;
  final bool showOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final paint = Paint()
      ..color = (cornerColor ?? Colors.amberAccent).withValues(alpha: 0.9)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (showOverlay) {
      final overlayPaint = Paint()
        ..color = (overlayColor ?? Colors.black).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      final overlayPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

      final docPath = Path()
        ..moveTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..lineTo(corners[2].dx, corners[2].dy)
        ..lineTo(corners[3].dx, corners[3].dy)
        ..close();

      overlayPath.addPath(docPath, Offset.zero);
      overlayPath.fillType = PathFillType.evenOdd;
      canvas.drawPath(overlayPath, overlayPaint);
    }

    final docPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(docPath, paint);

    for (var i = 0; i < 4; i++) {
      final corner = corners[i];
      canvas.drawCircle(corner, cornerRadius, paint..style = PaintingStyle.fill);
      canvas.drawCircle(
          corner, cornerRadius - strokeWidth / 2,
          Paint()
            ..color = (cornerColor ?? Colors.amberAccent)
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(DocumentCornersPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.showOverlay != showOverlay;
}
