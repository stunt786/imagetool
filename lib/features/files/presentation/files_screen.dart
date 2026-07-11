import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import 'file_preview_screen.dart';

class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top + 72;
    final files = ref.watch(editHistoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [scheme.surface, scheme.surfaceContainer, scheme.surface]
              : [Color(0xFFF8FAFF), Color(0xFFFCFAFF), Color(0xFFFFFCF8)],
        ),
      ),
      child: Stack(
        children: [
          if (!isDark) ...[
            const Positioned(
              top: -70,
              left: -30,
              child: _AmbientOrb(
                size: 220,
                colors: [Color(0xFFE0DEFF), Color(0x00E0DEFF)],
              ),
            ),
            const Positioned(
              top: 260,
              right: -50,
              child: _AmbientOrb(
                size: 200,
                colors: [Color(0xFFD8F6F4), Color(0x00D8F6F4)],
              ),
            ),
          ],
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    Row(
                      children: [
                        Text(
                          'My Files',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: scheme.primaryContainer,
                          ),
                          child: Text(
                            '${files.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (files.isNotEmpty)
                          TextButton(
                            onPressed: () => ref.read(editHistoryProvider.notifier).clear(),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (files.isEmpty)
                      _EmptyFiles(scheme: scheme, theme: theme)
                    else
                      ...List.generate(files.length, (i) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: i < files.length - 1 ? 14 : 0),
                          child: _FileTile(
                            item: files[i],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FilePreviewScreen(
                                  items: files,
                                  initialIndex: i,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({required this.scheme, required this.theme});

  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Icon(Icons.folder_open_rounded, color: scheme.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'No files yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Edited images and PDFs will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.item, this.onTap});

  final EditHistoryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isImage = !item.fileName.toLowerCase().endsWith('.pdf');

    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ThumbnailPreview(item: item, isImage: isImage),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _ToolBadge(tool: item.toolUsed),
                        const SizedBox(width: 8),
                        Text(
                          item.timeAgo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.compressionLevel != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '\u2022',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.compressionLevel!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onTertiaryContainer,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.open_in_new_rounded, size: 18, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPreview extends StatelessWidget {
  const _ThumbnailPreview({required this.item, required this.isImage});

  final EditHistoryItem item;
  final bool isImage;

  @override
  Widget build(BuildContext context) {
    final thumb = item.thumbnailPath;

    if (thumb != null && thumb.isNotEmpty && isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(thumb),
          width: 100,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    final gradient = isImage
        ? const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)]
        : const [Color(0xFF5B4DFF), Color(0xFF0F9D9A)];
    final icon = isImage ? Icons.image_outlined : Icons.picture_as_pdf_rounded;

    return Container(
      width: 100,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 32)),
    );
  }
}

class _ToolBadge extends StatelessWidget {
  const _ToolBadge({required this.tool});

  final String tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tool,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
