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
    this.isPdf = false,
    this.size = 56,
    this.borderRadius = 12,
  });

  final String path;
  final bool isPdf;
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
    _thumbnail = ThumbnailService.instance.thumbnailFor(
      widget.path,
      maxSide: widget.size <= 80 ? 160 : 360,
      isPdf: widget.isPdf,
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
    if (widget.isPdf) {
      return ColoredBox(
        color: const Color(0xFFF4511E),
        child: Center(
          child: Text(
            'PDF',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: widget.size * 0.26,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        size: widget.size * 0.42,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
