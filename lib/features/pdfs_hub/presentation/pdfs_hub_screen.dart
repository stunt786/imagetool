import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/widgets/shared_app_bar.dart';

const _pdfTools = <_PdfToolData>[
  _PdfToolData(
    title: 'Compress PDF',
    subtitle: 'Reduce file size for easy sharing and storage.',
    route: '/pdfs/compress',
    icon: Icons.compress_rounded,
    gradient: [Color(0xFFEDEBFF), Color(0xFFF8F7FF)],
    accent: Color(0xFF5B4DFF),
  ),
  _PdfToolData(
    title: 'Merge PDFs',
    subtitle: 'Combine multiple documents into one clean file.',
    route: '/pdfs/merge',
    icon: Icons.merge_type_rounded,
    gradient: [Color(0xFFE8FAF9), Color(0xFFF8FFFE)],
    accent: Color(0xFF0F9D9A),
  ),
  _PdfToolData(
    title: 'Split Pages',
    subtitle: 'Extract the pages you need into separate files.',
    route: '/pdfs/split',
    icon: Icons.call_split_rounded,
    gradient: [Color(0xFFFFF0E8), Color(0xFFFFFAF6)],
    accent: Color(0xFFEA580C),
  ),
  _PdfToolData(
    title: 'Convert PDF',
    subtitle: 'Transform PDFs into JPG, PNG, or TXT formats.',
    route: '/pdfs/convert',
    icon: Icons.transform_rounded,
    gradient: [Color(0xFFEAFBF0), Color(0xFFF8FFFB)],
    accent: Color(0xFF15803D),
  ),
];

class PdfsHubScreen extends ConsumerWidget {
  const PdfsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 1200
        ? 28.0
        : width >= 700
        ? 24.0
        : 18.0;
    final cardAspectRatio = width >= 1000
        ? 1.9
        : width >= 700
        ? 1.55
        : 0.82;

    final history = ref.watch(editHistoryProvider);
    final pdfHistory = history.where(_isPdfActivity).take(6).toList();

    return Scaffold(
      appBar: SharedAppBar(
        drawerKey: GlobalKey<ScaffoldState>(),
        title: 'PDFs',
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [scheme.surface, scheme.surfaceContainer, scheme.surface]
                : const [
                    Color(0xFFF8FAFF),
                    Color(0xFFFCFAFF),
                    Color(0xFFFFFCF8),
                  ],
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
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'PDF Tools',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                          ),
                          Text(
                            '${_pdfTools.length} tools',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        itemCount: _pdfTools.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: cardAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          return _PdfToolCard(data: _pdfTools[index]);
                        },
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Historical Activity',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                          ),
                          if (pdfHistory.isNotEmpty)
                            TextButton(
                              onPressed: () => ref
                                  .read(editHistoryProvider.notifier)
                                  .clear(),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (pdfHistory.isEmpty)
                        const _EmptyPdfHistoryCard()
                      else
                        ...pdfHistory.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _PdfHistoryRow(item: item),
                          ),
                        ),
                      const SizedBox(height: 120),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfToolCard extends StatefulWidget {
  const _PdfToolCard({required this.data});

  final _PdfToolData data;

  @override
  State<_PdfToolCard> createState() => _PdfToolCardState();
}

class _PdfToolCardState extends State<_PdfToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = widget.data;
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        InterstitialTracker.instance.trackNavigation();
        context.push(data.route);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: data.gradient,
            ),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: data.accent.withValues(alpha: isDark ? 0.06 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (isDark)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(child: _PdfToolArtwork(data: data)),
                    const Spacer(),
                    Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfToolArtwork extends StatelessWidget {
  const _PdfToolArtwork({required this.data});

  final _PdfToolData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(data.icon, color: data.accent, size: 30),
    );
  }
}

class _PdfHistoryRow extends StatelessWidget {
  const _PdfHistoryRow({required this.item});

  final EditHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.86),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5B4DFF), Color(0xFF0F9D9A)],
              ),
            ),
            child: Icon(item.toolIcon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.toolUsed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.timeAgo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening ${item.fileName} soon.')),
              );
            },
            icon: Icon(Icons.open_in_new_rounded, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

class _EmptyPdfHistoryCard extends StatelessWidget {
  const _EmptyPdfHistoryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEDEBFF), Color(0xFFE8FAF9)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Your recent PDF activity will appear here after you compress, merge, or split documents.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
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

class _PdfToolData {
  const _PdfToolData({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.gradient,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final List<Color> gradient;
  final Color accent;
}

bool _isPdfActivity(EditHistoryItem item) {
  final lowerFileName = item.fileName.toLowerCase();
  final lowerTool = item.toolUsed.toLowerCase();

  return lowerFileName.endsWith('.pdf') || lowerTool.contains('pdf');
}
