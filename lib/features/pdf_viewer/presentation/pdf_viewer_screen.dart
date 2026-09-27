import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

/// Full in-app PDF viewer: continuous vertical pages, pinch-to-zoom, page
/// indicator, loading and error states.
///
/// Reuses the `pdfx` renderer that is already a dependency of the app, so no
/// external viewer is launched unless the user explicitly chooses to share.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.filePath,
    this.title,
    this.initialPage = 1,
  });

  final String filePath;

  /// Shown in the app bar; falls back to the file name.
  final String? title;

  final int initialPage;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  pdfx.PdfControllerPinch? _controller;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = true;
  String? _error;
  bool _fileExists = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _openDocument();
  }

  void _openDocument() {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      setState(() {
        _isLoading = false;
        _fileExists = false;
        _error = 'This file is no longer available.';
      });
      return;
    }

    try {
      _controller = pdfx.PdfControllerPinch(
        document: pdfx.PdfDocument.openFile(widget.filePath),
        initialPage: widget.initialPage,
      );
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'This PDF could not be opened.';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _displayTitle {
    if (widget.title != null && widget.title!.isNotEmpty) return widget.title!;
    final parts = widget.filePath.split(Platform.pathSeparator);
    return parts.isEmpty ? 'PDF' : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(
          _displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_pageCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_currentPage / $_pageCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Share PDF',
            onPressed: _fileExists ? _share : null,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return _buildMessage(
        theme,
        icon: _fileExists
            ? Icons.picture_as_pdf_outlined
            : Icons.error_outline_rounded,
        title: _error!,
        detail: _fileExists
            ? 'The document may be corrupted or password protected.'
            : 'It may have been moved or deleted.',
      );
    }

    final controller = _controller;
    if (controller == null) {
      return _buildMessage(
        theme,
        icon: Icons.picture_as_pdf_outlined,
        title: 'Nothing to show',
        detail: null,
      );
    }

    return Stack(
      children: [
        pdfx.PdfViewPinch(
          controller: controller,
          minScale: 1.0,
          maxScale: 6.0,
          padding: 12,
          backgroundDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          onDocumentLoaded: (document) {
            if (!mounted) return;
            setState(() {
              _pageCount = document.pagesCount;
              _isLoading = false;
            });
          },
          onDocumentError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = 'This PDF could not be displayed.';
            });
          },
          onPageChanged: (page) {
            if (!mounted || page == _currentPage) return;
            setState(() => _currentPage = page);
          },
        ),
        if (_isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_pageCount > 1 && _currentPage == 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface
                        .withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Scroll for more pages · pinch to zoom',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessage(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.filePath)],
        subject: _displayTitle,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this PDF.')),
      );
    }
  }
}
