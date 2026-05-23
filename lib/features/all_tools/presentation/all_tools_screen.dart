import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/interstitial_tracker.dart';

const _imageTools = <_ToolData>[
  _ToolData(
    title: 'Resize Image',
    subtitle: 'Resize by pixels, aspect ratio, or presets.',
    route: '/images/resizer',
    icon: Icons.photo_size_select_large_rounded,
    accent: Color(0xFF2563EB),
  ),
  _ToolData(
    title: 'Create Collage',
    subtitle: 'Arrange photos into polished layouts.',
    route: '/images/collage',
    icon: Icons.dashboard_customize_rounded,
    accent: Color(0xFF9333EA),
  ),
  _ToolData(
    title: 'Format Converter',
    subtitle: 'Switch between JPG, PNG, WEBP, and more.',
    route: '/images/convert',
    icon: Icons.autorenew_rounded,
    accent: Color(0xFF15803D),
  ),
  _ToolData(
    title: 'Image to PDF',
    subtitle: 'Turn scans and photos into PDF documents.',
    route: '/images/to-pdf',
    icon: Icons.picture_as_pdf_rounded,
    accent: Color(0xFFEA580C),
  ),
];

const _pdfTools = <_ToolData>[
  _ToolData(
    title: 'Compress PDF',
    subtitle: 'Reduce file size for easy sharing.',
    route: '/pdfs/compress',
    icon: Icons.compress_rounded,
    accent: Color(0xFF5B4DFF),
  ),
  _ToolData(
    title: 'Merge PDFs',
    subtitle: 'Combine documents into one file.',
    route: '/pdfs/merge',
    icon: Icons.merge_type_rounded,
    accent: Color(0xFF0F9D9A),
  ),
  _ToolData(
    title: 'Split Pages',
    subtitle: 'Extract pages into separate files.',
    route: '/pdfs/split',
    icon: Icons.call_split_rounded,
    accent: Color(0xFFEA580C),
  ),
  _ToolData(
    title: 'Convert PDF',
    subtitle: 'Transform PDFs into JPG, PNG, or TXT.',
    route: '/pdfs/convert',
    icon: Icons.transform_rounded,
    accent: Color(0xFF15803D),
  ),
];

class AllToolsScreen extends StatelessWidget {
  const AllToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.only(left: 4),
              child:               IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
                onPressed: () => GoRouter.of(context).go('/tools'),
              ),
            ),
            title: Text(
              'All Tools',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                _CategoryHeader(title: 'Image Tools', count: _imageTools.length),
                const SizedBox(height: 12),
                ...List.generate(_imageTools.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: i < _imageTools.length - 1 ? 12 : 24),
                    child: _ToolRow(data: _imageTools[i]),
                  );
                }),
                _CategoryHeader(title: 'PDF Tools', count: _pdfTools.length),
                const SizedBox(height: 12),
                ...List.generate(_pdfTools.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: i < _pdfTools.length - 1 ? 12 : 0),
                    child: _ToolRow(data: _pdfTools[i]),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
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
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.data});

  final _ToolData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          InterstitialTracker.instance.trackNavigation();
          GoRouter.of(context).go(data.route);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: data.accent.withValues(alpha: 0.12),
                ),
                child: Icon(data.icon, size: 22, color: data.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolData {
  const _ToolData({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color accent;
}
