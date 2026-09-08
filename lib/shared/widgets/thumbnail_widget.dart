import 'dart:io';

import 'package:flutter/material.dart';

import '../models/edit_history_item.dart';

/// Reusable thumbnail preview for a history item.
/// Shows the actual image if thumbnailPath is available, otherwise a gradient fallback.
class HistoryThumbnail extends StatelessWidget {
  const HistoryThumbnail({
    super.key,
    required this.item,
    this.width = 56,
    this.height = 56,
    this.borderRadius = 12,
  });

  final EditHistoryItem item;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isImage = !item.fileName.toLowerCase().endsWith('.pdf');
    final thumb = item.thumbnailPath;

    if (thumb != null && thumb.isNotEmpty && isImage) {
      final file = File(thumb);
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(isImage),
        ),
      );
    }
    return _buildFallback(isImage);
  }

  Widget _buildFallback(bool isImage) {
    final gradient = isImage
        ? const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)]
        : const [Color(0xFF5B4DFF), Color(0xFF0F9D9A)];
    final icon = isImage ? Icons.image_outlined : Icons.picture_as_pdf_rounded;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: width * 0.45)),
    );
  }
}
