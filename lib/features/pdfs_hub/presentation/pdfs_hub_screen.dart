import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';

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
];

class PdfsHubScreen extends ConsumerWidget {
  const PdfsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: padding,
        title: Text(
          'PDFs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFF), Color(0xFFFCFAFF), Color(0xFFFFFCF8)],
          ),
        ),
        child: Stack(
          children: [
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
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      const _PdfsHeroCard(),
                      const SizedBox(height: 28),
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
                              color: const Color(0xFF5B4DFF),
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

class _PdfsHeroCard extends StatelessWidget {
  const _PdfsHeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171A3A), Color(0xFF3D37A4), Color(0xFF0F9D9A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2217203A),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Document workflow',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Manage, compress, and organize your PDF files faster.',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The PDF hub now keeps your recent document activity visible so you can continue work without hunting through folders.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
        ],
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
    final data = widget.data;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        context.go(data.route);
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: data.accent.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
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
                    color: const Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data.subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF526077),
                    height: 1.35,
                  ),
                ),
              ],
            ),
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
        color: Colors.white,
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        border: Border.all(color: const Color(0xFFEDEAF6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 18,
            offset: Offset(0, 10),
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
                    color: const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.timeAgo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A94A6),
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
            icon: const Icon(
              Icons.open_in_new_rounded,
              color: Color(0xFF5B4DFF),
            ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        border: Border.all(color: const Color(0xFFEDEAF6)),
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
            child: const Icon(Icons.history_rounded, color: Color(0xFF5B4DFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Your recent PDF activity will appear here after you compress, merge, or split documents.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF667085),
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
