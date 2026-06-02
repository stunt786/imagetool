import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

import '../../../../shared/notifiers/image_edit_notifier.dart';
import '../../../format_converter/notifiers/format_converter_notifier.dart';
import '../../../image_to_pdf/notifiers/image_to_pdf_notifier.dart';
import '../../../camera/notifiers/document_batch_notifier.dart';

class PostCaptureMenu extends ConsumerStatefulWidget {
  const PostCaptureMenu({
    super.key,
    required this.imagePath,
    required this.isDocumentMode,
    required this.onRetake,
  });

  final String imagePath;
  final bool isDocumentMode;
  final VoidCallback onRetake;

  @override
  ConsumerState<PostCaptureMenu> createState() => _PostCaptureMenuState();
}

class _PostCaptureMenuState extends ConsumerState<PostCaptureMenu> {
  bool _isLoading = false;

  Future<void> _routeToResize() async {
    setState(() => _isLoading = true);
    try {
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();
      final name = path.basename(widget.imagePath);
      await ref.read(imageEditProvider.notifier).loadImage(bytes, name);
      if (mounted) {
        context.push('/images/resizer');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeToFormatConvert() async {
    setState(() => _isLoading = true);
    try {
      final file = File(widget.imagePath);
      final bytes = await file.length();
      final name = path.basename(widget.imagePath);
      await ref.read(formatConverterProvider.notifier).addImages([
        {'path': widget.imagePath, 'name': name, 'sizeBytes': bytes}
      ]);
      if (mounted) {
        context.push('/images/convert');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeToPdf() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(imageToPdfProvider.notifier)
          .addImageFromPath(widget.imagePath);
      if (mounted) {
        context.push('/images/to-pdf');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeToFilters() async {
    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(documentBatchProvider.notifier);
      if (!ref.read(documentBatchProvider).hasPages) {
        notifier.startNewBatch();
      }
      await notifier.addPageFromPath(widget.imagePath);
      if (mounted) {
        final batch = ref.read(documentBatchProvider);
        final index = batch.pages.length - 1;
        context.push('/camera/filter', extra: index);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeToCorrectPerspective() async {
    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(documentBatchProvider.notifier);
      if (!ref.read(documentBatchProvider).hasPages) {
        notifier.startNewBatch();
      }
      await notifier.addPageFromPath(widget.imagePath);
      if (mounted) {
        final batch = ref.read(documentBatchProvider);
        final index = batch.pages.length - 1;
        context.push('/camera/correct-perspective', extra: index);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next Steps',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton.icon(
                onPressed: _isLoading ? null : widget.onRetake,
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('Retake'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isDocumentMode) ...[
            _ActionTile(
              icon: Icons.auto_fix_high_rounded,
              title: 'Apply Filters',
              subtitle: 'Magic Color, Binarization, Shadow Removal',
              color: Colors.purple,
              onTap: _isLoading ? null : _routeToFilters,
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.transform_rounded,
              title: 'Correct Perspective',
              subtitle: 'Fix skewed document corners',
              color: Colors.teal,
              onTap: _isLoading ? null : _routeToCorrectPerspective,
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Convert to PDF',
              subtitle: 'Ideal for scanned documents',
              color: Colors.red,
              onTap: _isLoading ? null : _routeToPdf,
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.transform_rounded,
              title: 'Resize or Compress',
              subtitle: 'Adjust dimensions & quality',
              color: scheme.primary,
              onTap: _isLoading ? null : _routeToResize,
            ),
          ] else ...[
            _ActionTile(
              icon: Icons.transform_rounded,
              title: 'Resize & Edit',
              subtitle: 'Crop, resize, or compress image',
              color: scheme.primary,
              onTap: _isLoading ? null : _routeToResize,
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.compare_arrows_rounded,
              title: 'Format Change',
              subtitle: 'Convert to PNG, BMP, etc.',
              color: Colors.green,
              onTap: _isLoading ? null : _routeToFormatConvert,
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Convert to PDF',
              subtitle: 'Create a PDF document',
              color: Colors.red,
              onTap: _isLoading ? null : _routeToPdf,
            ),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.9),
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
