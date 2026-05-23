import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/widgets/premium_banner.dart';

const _featuredTools = <_QuickToolData>[
  _QuickToolData(
    title: 'Resize Image',
    subtitle: 'Resize by pixels, aspect ratio, or ready-made presets.',
    icon: Icons.photo_size_select_large_rounded,
    route: '/images/resizer',
    gradient: [Color(0xFFEAF3FF), Color(0xFFF7FAFF)],
    accent: Color(0xFF2563EB),
    glow: Color(0xFFD8E8FF),
  ),
  _QuickToolData(
    title: 'Create Collage',
    subtitle: 'Arrange multiple photos into polished social-ready layouts.',
    icon: Icons.dashboard_customize_rounded,
    route: '/images/collage',
    gradient: [Color(0xFFF7EDFF), Color(0xFFFEF7FF)],
    accent: Color(0xFF9333EA),
    glow: Color(0xFFEDD9FF),
  ),
  _QuickToolData(
    title: 'Format Converter',
    subtitle: 'Switch between JPG, PNG, WEBP, and more in seconds.',
    icon: Icons.autorenew_rounded,
    route: '/images/convert',
    gradient: [Color(0xFFEAFBF0), Color(0xFFF8FFFB)],
    accent: Color(0xFF15803D),
    glow: Color(0xFFD8F5E1),
  ),
  _QuickToolData(
    title: 'Image to PDF',
    subtitle: 'Convert images to PDF documents instantly.',
    icon: Icons.picture_as_pdf_rounded,
    route: '/images/to-pdf',
    gradient: [Color(0xFFFFF0ED), Color(0xFFFFF8F7)],
    accent: Color(0xFFE64A19),
    glow: Color(0xFFFFD8CC),
  ),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_QuickToolData> get _filteredTools {
    if (_searchQuery.isEmpty) return _featuredTools;
    return _featuredTools
        .where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<EditHistoryItem> _filteredHistory(List<EditHistoryItem> history) {
    if (_searchQuery.isEmpty) return [];
    return history
        .where((item) =>
            item.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            item.toolUsed.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final history = ref.watch(editHistoryProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final contentPadding = width >= 1200
        ? 28.0
        : width >= 700
        ? 24.0
        : 18.0;
    final topPadding = MediaQuery.of(context).padding.top + 12;

    final filteredTools = _filteredTools;
    final filteredHistory = _filteredHistory(history);
    final isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [scheme.surface, scheme.surfaceContainer, scheme.surface]
                : const [Color(0xFFFDF7FF), Color(0xFFF9FBFF), Color(0xFFFFFCF8)],
          ),
        ),
        child: Stack(
          children: [
            if (!isDark) ...[
              const Positioned(
                top: -80,
                left: -40,
                child: _AmbientOrb(
                  size: 220,
                  colors: [Color(0xFFC9D9FF), Color(0x00C9D9FF)],
                ),
              ),
              const Positioned(
                top: 220,
                right: -70,
                child: _AmbientOrb(
                  size: 250,
                  colors: [Color(0xFFFFD7F4), Color(0x00FFD7F4)],
                ),
              ),
              const Positioned(
                bottom: 120,
                left: -60,
                child: _AmbientOrb(
                  size: 210,
                  colors: [Color(0xFFD9FFD9), Color(0x00D9FFD9)],
                ),
              ),
            ],
            Column(
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(contentPadding, topPadding, contentPadding, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(23),
                            color: scheme.surfaceContainerLowest,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _searchQuery = value),
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search tools...',
                              hintStyle: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              suffixIcon: isSearching
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEAB308).withValues(alpha: 0.12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.workspace_premium_rounded,
                              size: 20, color: Color(0xFFEAB308)),
                          onPressed: () => context.push('/premium'),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isSearching && filteredTools.isEmpty && filteredHistory.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded, size: 48,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No results found for "$_searchQuery"',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: isSearching
                  ? ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(contentPadding, 16, contentPadding, 110),
                      children: [
                        if (filteredTools.isNotEmpty) ...[
                          _SectionHeader(title: 'Tools'),
                          const SizedBox(height: 12),
                          ...filteredTools.map(
                            (tool) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SearchToolRow(data: tool),
                            ),
                          ),
                        ],
                        if (filteredHistory.isNotEmpty) ...[
                          if (filteredTools.isNotEmpty) const SizedBox(height: 8),
                          _SectionHeader(title: 'Files'),
                          const SizedBox(height: 12),
                          ...filteredHistory.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistoryRow(item: item),
                            ),
                          ),
                        ],
                      ],
                    )
                  : CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            contentPadding,
                            16,
                            contentPadding,
                            0,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed([
                              Text(
                                'Explore Tools',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _SectionHeader(
                                title: 'Featured',
                                actionLabel: 'View All',
                                onActionTap: () => context.push('/all-tools'),
                              ),
                              const SizedBox(height: 14),
                              _FeaturedToolsGrid(isWide: isWide),
                              const SizedBox(height: 18),
                              const PremiumBanner(),
                              const SizedBox(height: 28),
                              _SectionHeader(
                                title: 'Recent History',
                                actionLabel: history.isNotEmpty ? 'See All' : null,
                                onActionTap: history.isNotEmpty
                                    ? () => context.push('/files')
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              if (history.isEmpty)
                                const _EmptyHistoryCard()
                              else
                                ...history
                                    .take(10)
                                    .map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(bottom: 14),
                                        child: _HistoryRow(item: item),
                                      ),
                                    ),
                              if (history.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => ref
                                          .read(editHistoryProvider.notifier)
                                          .clear(),
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      label: const Text('Clear history'),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 110),
                            ]),
                          ),
                        ),
                      ],
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

class _FeaturedToolsGrid extends StatelessWidget {
  const _FeaturedToolsGrid({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: _featuredTools.length,
      itemBuilder: (context, index) => Center(
        child: _FeatureIcon(data: _featuredTools[index]),
      ),
    );
  }
}

class _FeatureIcon extends StatefulWidget {
  const _FeatureIcon({required this.data});

  final _QuickToolData data;

  @override
  State<_FeatureIcon> createState() => _FeatureIconState();
}

class _FeatureIconState extends State<_FeatureIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = widget.data;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        InterstitialTracker.instance.trackNavigation();
        context.push(data.route);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    data.accent,
                    Color.lerp(data.accent, Colors.white, 0.3)!,
                  ],
                ),
              ),
              child: Icon(data.icon, size: 22, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchToolRow extends StatelessWidget {
  const _SearchToolRow({required this.data});

  final _QuickToolData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        InterstitialTracker.instance.trackNavigation();
        context.push(data.route);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    data.accent,
                    Color.lerp(data.accent, Colors.white, 0.3)!,
                  ],
                ),
              ),
              child: Icon(data.icon, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final EditHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitleColor = scheme.onSurfaceVariant;
    final timeParts = _historyTimeParts(item.editedAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
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
          _HistoryThumbnail(item: item),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (MediaQuery.sizeOf(context).width >= 560)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeParts.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeParts.$2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          _ActionCircleButton(
            icon: Icons.open_in_new_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Opened ${item.fileName} details soon.'),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          _ActionCircleButton(
            icon: Icons.more_horiz_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('More actions for ${item.fileName} soon.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryThumbnail extends StatelessWidget {
  const _HistoryThumbnail({required this.item});

  final EditHistoryItem item;

  @override
  Widget build(BuildContext context) {
    if (item.thumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(
          File(item.thumbnailPath!),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildGradientFallback(),
        ),
      );
    }
    return _buildGradientFallback();
  }

  Widget _buildGradientFallback() {
    final gradient = _historyGradient(item.toolUsed);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -6,
            bottom: -6,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
          ),
          Center(child: Icon(item.toolIcon, color: Colors.white, size: 30)),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE8EBFF), Color(0xFFFFE4F5)],
              ),
            ),
            child: const Icon(Icons.history_rounded, color: Color(0xFF6B5BFF)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Recent edits will appear here after you start using the tools.',
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (actionLabel != null && onActionTap != null)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onActionTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, color: scheme.primary),
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

class _QuickToolData {
  const _QuickToolData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.gradient,
    required this.accent,
    required this.glow,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final List<Color> gradient;
  final Color accent;
  final Color glow;
}

(String, String) _historyTimeParts(DateTime editedAt) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfEdited = DateTime(editedAt.year, editedAt.month, editedAt.day);
  final dayDiff = startOfToday.difference(startOfEdited).inDays;

  final dateLabel = switch (dayDiff) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => '${editedAt.month}/${editedAt.day}/${editedAt.year}',
  };

  final hour = editedAt.hour % 12 == 0 ? 12 : editedAt.hour % 12;
  final minute = editedAt.minute.toString().padLeft(2, '0');
  final suffix = editedAt.hour >= 12 ? 'PM' : 'AM';

  return (dateLabel, '$hour:$minute $suffix');
}

List<Color> _historyGradient(String tool) {
  if (tool.contains('Resize')) {
    return const [Color(0xFF4F9CFF), Color(0xFF7BD5FF)];
  }
  if (tool.contains('Collage')) {
    return const [Color(0xFF8B5CFF), Color(0xFFE252FF)];
  }
  if (tool.contains('PDF')) {
    return const [Color(0xFFFF6B5D), Color(0xFFFFA85B)];
  }
  if (tool.contains('Format')) {
    return const [Color(0xFF11B67A), Color(0xFF69D66E)];
  }

  final hue = tool.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 360;
  final color = HSVColor.fromAHSV(1, hue.toDouble(), 0.65, 0.9).toColor();

  return [color, Color.lerp(color, Colors.white, 0.35)!];
}
