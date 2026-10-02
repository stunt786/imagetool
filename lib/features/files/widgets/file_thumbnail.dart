import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/services/thumbnail_service.dart';

/// Square preview for a file row or grid tile.
///
/// Previews are produced and cached by [ThumbnailService], so scrolling a long
/// list never re-renders a PDF and only decodes an image once.
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    super.key,
    required this.path,
    this.isPdf,
    this.size = 56,
    this.borderRadius = 12,
  });

  final String path;
  final bool? isPdf;
  final double size;
  final double borderRadius;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Future<String?>? _thumbnail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.isPdf != widget.isPdf) {
      _load();
    }
  }

  void _load() {
    final actualIsPdf =
        (widget.isPdf ?? false) || widget.path.toLowerCase().endsWith('.pdf');
    _thumbnail = ThumbnailService.instance.thumbnailFor(
      widget.path,
      maxSide: widget.size <= 80 ? 160 : 360,
      isPdf: actualIsPdf,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<String?>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final thumbnailPath = snapshot.data;
            if (thumbnailPath != null) {
              return Image.file(
                File(thumbnailPath),
                fit: BoxFit.cover,
                width: widget.size,
                height: widget.size,
                cacheWidth: widget.size.ceil() * 3,
                cacheHeight: widget.size.ceil() * 3,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(scheme),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: SizedBox(
                    width: widget.size * 0.3,
                    height: widget.size * 0.3,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _placeholder(scheme);
          },
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    final lower = widget.path.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.csv')) {
      return Container(
        color: const Color(0xFF1B3D2F),
        child: Center(
          child: Container(
            width: widget.size * 0.6,
            height: widget.size * 0.6,
            decoration: BoxDecoration(
              color: const Color(0xFF00C853),
              borderRadius: BorderRadius.circular(widget.borderRadius * 0.6),
            ),
            child: Center(
              child: Text(
                'X',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: widget.size * 0.32,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) {
      return Container(
        color: const Color(0xFF3E2723),
        child: Center(
          child: Container(
            width: widget.size * 0.6,
            height: widget.size * 0.6,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6D00),
              borderRadius: BorderRadius.circular(widget.borderRadius * 0.6),
            ),
            child: Center(
              child: Text(
                'P',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: widget.size * 0.32,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (lower.endsWith('.docx') || lower.endsWith('.doc')) {
      return Container(
        color: const Color(0xFF1A237E),
        child: Center(
          child: Container(
            width: widget.size * 0.6,
            height: widget.size * 0.6,
            decoration: BoxDecoration(
              color: const Color(0xFF2979FF),
              borderRadius: BorderRadius.circular(widget.borderRadius * 0.6),
            ),
            child: Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: widget.size * 0.32,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if ((widget.isPdf ?? false) || lower.endsWith('.pdf')) {
      return Container(
        color: const Color(0xFF2B1D1D),
        child: Center(
          child: Container(
            width: widget.size * 0.62,
            height: widget.size * 0.62,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(widget.borderRadius * 0.6),
            ),
            child: Center(
              child: Text(
                'PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: widget.size * 0.22,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        size: widget.size * 0.42,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
