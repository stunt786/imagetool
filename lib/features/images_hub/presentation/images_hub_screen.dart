import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/shared_app_bar.dart';

const _imageTools = <_ImageToolData>[
  _ImageToolData(
    title: 'Resize Image',
    subtitle: 'Resize batches with custom ratios and export presets.',
    route: '/images/resizer',
    icon: Icons.photo_size_select_large_rounded,
    gradient: [Color(0xFFEAF3FF), Color(0xFFF7FAFF)],
    accent: Color(0xFF2563EB),
  ),
  _ImageToolData(
    title: 'Create Collage',
    subtitle: 'Build polished layouts for stories, reels, and albums.',
    route: '/images/collage',
    icon: Icons.dashboard_customize_rounded,
    gradient: [Color(0xFFF7EDFF), Color(0xFFFEF7FF)],
    accent: Color(0xFF9333EA),
  ),
  _ImageToolData(
    title: 'Format Converter',
    subtitle: 'Switch between JPG, PNG, WEBP, and lightweight exports.',
    route: '/images/convert',
    icon: Icons.autorenew_rounded,
    gradient: [Color(0xFFEAFBF0), Color(0xFFF8FFFB)],
    accent: Color(0xFF15803D),
  ),
  _ImageToolData(
    title: 'Image to PDF',
    subtitle: 'Combine scans and pictures into crisp PDF documents.',
    route: '/images/to-pdf',
    icon: Icons.picture_as_pdf_rounded,
    gradient: [Color(0xFFFFF1E7), Color(0xFFFFFAF5)],
    accent: Color(0xFFEA580C),
  ),
];

class ImagesHubScreen extends StatelessWidget {
  const ImagesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final padding = width >= 1200
        ? 28.0
        : width >= 700
        ? 24.0
        : 18.0;
    final cardAspectRatio = width >= 1000
        ? 1.85
        : width >= 700
        ? 1.45
        : 0.8;

    return Scaffold(
      appBar: SharedAppBar(
        drawerKey: GlobalKey<ScaffoldState>(),
        title: 'Images',
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7FAFF), Color(0xFFFDF7FF), Color(0xFFFFFCF7)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -70,
              right: -30,
              child: _AmbientOrb(
                size: 220,
                colors: [Color(0xFFD9E4FF), Color(0x00D9E4FF)],
              ),
            ),
            const Positioned(
              top: 240,
              left: -60,
              child: _AmbientOrb(
                size: 200,
                colors: [Color(0xFFEAD6FF), Color(0x00EAD6FF)],
              ),
            ),
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
                              'All Image Tools',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                          ),
                          Text(
                            '${_imageTools.length} tools',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF7C3AED),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        itemCount: _imageTools.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: cardAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          return _ImageToolCard(data: _imageTools[index]);
                        },
                      ),
                      const SizedBox(height: 22),
                      const _ImageTipsCard(),
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

class _ImageToolCard extends StatefulWidget {
  const _ImageToolCard({required this.data});

  final _ImageToolData data;

  @override
  State<_ImageToolCard> createState() => _ImageToolCardState();
}

class _ImageToolCardState extends State<_ImageToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        context.push(data.route);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
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
          child: Stack(
            children: [
              Positioned(
                right: -10,
                top: -10,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(child: _ImageToolArtwork(data: data)),
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF526077),
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

class _ImageToolArtwork extends StatelessWidget {
  const _ImageToolArtwork({required this.data});

  final _ImageToolData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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

class _ImageTipsCard extends StatelessWidget {
  const _ImageTipsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withValues(alpha: 0.82),
        border: Border.all(color: const Color(0xFFE9EAF4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFDBEAFE), Color(0xFFEDE9FE)],
              ),
            ),
            child: const Icon(
              Icons.tips_and_updates_rounded,
              color: Color(0xFF5B4DFF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Designed for quick scanning',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Each card is larger, more visual, and kept in a two-column grid so the tab feels closer to the attached reference.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF667085),
                    height: 1.45,
                  ),
                ),
              ],
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

class _ImageToolData {
  const _ImageToolData({
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
