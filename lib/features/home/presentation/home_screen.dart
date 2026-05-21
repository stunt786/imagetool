import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/interstitial_tracker.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../../../shared/widgets/shared_app_bar.dart';

const _quickTools = <_QuickToolData>[
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
    subtitle: 'Turn scans and photos into neat, shareable PDF documents.',
    icon: Icons.picture_as_pdf_rounded,
    route: '/images/to-pdf',
    gradient: [Color(0xFFFFF1E7), Color(0xFFFFFAF5)],
    accent: Color(0xFFEA580C),
    glow: Color(0xFFFFE3CD),
  ),
];

const _pdfShortcuts = <_ShortcutChipData>[
  _ShortcutChipData(
    title: 'Compress PDF',
    icon: Icons.compress_rounded,
    route: '/pdfs/compress',
    tint: Color(0xFF6F63FF),
  ),
  _ShortcutChipData(
    title: 'Merge PDFs',
    icon: Icons.merge_type_rounded,
    route: '/pdfs/merge',
    tint: Color(0xFF00A6A6),
  ),
  _ShortcutChipData(
    title: 'Split Pages',
    icon: Icons.call_split_rounded,
    route: '/pdfs/split',
    tint: Color(0xFFFF7A59),
  ),
  _ShortcutChipData(
    title: 'Convert PDF',
    icon: Icons.transform_rounded,
    route: '/pdfs/convert',
    tint: Color(0xFF15803D),
  ),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _outputFolder = 'Default app folder';
  String _watermarkText = 'PixelTools';
  bool _keepExifData = true;

  Future<void> _editOutputFolder() async {
    final controller = TextEditingController(text: _outputFolder);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change output folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Example: Pictures/PixelTools',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _outputFolder = result);
  }

  Future<void> _editWatermarkText() async {
    final controller = TextEditingController(text: _watermarkText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom text watermark'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter watermark text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _watermarkText = result);
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help'),
        content: const Text(
          'Use Quick Tools for fast actions, the Images tab for visual workflows, and Recent History to reopen your latest work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showContact() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact us'),
        content: const Text(
          'Reach us at support@pixeltools.app for feedback, feature requests, or bug reports.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareApp() async {
    await Share.share(
      'Edit images and PDFs offline with ${AppStrings.appName}.',
      subject: AppStrings.appName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(editHistoryProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final contentPadding = width >= 1200
        ? 28.0
        : width >= 700
        ? 24.0
        : 18.0;

    return Scaffold(
      key: _scaffoldKey,
      drawer: SharedAppDrawer(
        outputFolder: _outputFolder,
        watermarkText: _watermarkText,
        keepExifData: _keepExifData,
        onUpgradeTap: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Premium plans are coming soon.')),
          );
        },
        onSettingsTap: () {
          Navigator.of(context).pop();
          context.go('/settings');
        },
        onOutputFolderTap: _editOutputFolder,
        onWatermarkTap: _editWatermarkText,
        onKeepExifChanged: (value) => setState(() => _keepExifData = value),
        onHelpTap: _showHelp,
        onContactTap: _showContact,
        onShareTap: _shareApp,
      ),
      appBar: SharedAppBar(drawerKey: _scaffoldKey),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDF7FF), Color(0xFFF9FBFF), Color(0xFFFFFCF8)],
          ),
        ),
        child: Stack(
          children: [
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
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: contentPadding),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      const SizedBox(height: 16),
                      _SectionHeader(
                        title: 'Quick Tools',
                        actionLabel: 'View All',
                        onActionTap: () => context.push('/images'),
                      ),
                      const SizedBox(height: 14),
                      _QuickToolsGrid(isWide: isWide),
                      const SizedBox(height: 18),
                      _PdfShortcutRail(shortcuts: _pdfShortcuts),
                      const SizedBox(height: 18),
                      const _PremiumBanner(),
                      const SizedBox(height: 28),
                      _SectionHeader(
                        title: 'Recent History',
                        actionLabel: history.isNotEmpty ? 'See All' : null,
                        onActionTap: history.isNotEmpty
                            ? () => context.push('/images')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      if (history.isEmpty)
                        const _EmptyHistoryCard()
                      else
                        ...history
                            .take(6)
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
          ],
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1F45), Color(0xFF4338CA), Color(0xFF0F9D9A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221C2459),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.14),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade to Premium',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Get advanced export presets, pro batch tools, and premium editing features.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF312E81),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Premium plans are coming soon.')),
              );
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}



class _QuickToolsGrid extends StatelessWidget {
  const _QuickToolsGrid({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: _quickTools.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: isWide ? 2.0 : 0.8,
      ),
      itemBuilder: (context, index) {
        final tool = _quickTools[index];
        return _QuickToolCard(data: tool);
      },
    );
  }
}

class _QuickToolCard extends StatefulWidget {
  const _QuickToolCard({required this.data});

  final _QuickToolData data;

  @override
  State<_QuickToolCard> createState() => _QuickToolCardState();
}

class _QuickToolCardState extends State<_QuickToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    final isWide = MediaQuery.sizeOf(context).width >= 900;

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
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: data.gradient,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: data.glow.withValues(alpha: 0.65),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 90,
                  height: 90,
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
                    Center(child: _QuickToolArtwork(data: data)),
                    const Spacer(),
                    Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: const Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.subtitle,
                      maxLines: isWide ? 2 : 3,
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

class _QuickToolArtwork extends StatelessWidget {
  const _QuickToolArtwork({required this.data});

  final _QuickToolData data;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: isWide ? 52 : 46,
              height: isWide ? 52 : 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    data.accent,
                    Color.lerp(data.accent, Colors.white, 0.4)!,
                  ],
                ),
              ),
            ),
            Icon(data.icon, size: isWide ? 30 : 26, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _PdfShortcutRail extends StatelessWidget {
  const _PdfShortcutRail({required this.shortcuts});

  final List<_ShortcutChipData> shortcuts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withValues(alpha: 0.82),
        border: Border.all(color: const Color(0xFFE9E7F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: shortcuts
            .map((shortcut) => _PdfShortcutChip(data: shortcut))
            .toList(),
      ),
    );
  }
}

class _PdfShortcutChip extends StatelessWidget {
  const _PdfShortcutChip({required this.data});

  final _ShortcutChipData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        InterstitialTracker.instance.trackNavigation();
        context.push(data.route);
      },
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: data.tint.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: data.tint.withValues(alpha: 0.14),
              ),
              child: Icon(data.icon, size: 18, color: data.tint),
            ),
            const SizedBox(width: 10),
            Text(
              data.title,
              style: TextStyle(color: data.tint, fontWeight: FontWeight.w700),
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
    final subtitleColor = const Color(0xFF6B7280);
    final timeParts = _historyTimeParts(item.editedAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.84),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.82),
        border: Border.all(color: const Color(0xFFEDEAF6)),
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

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
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
                      color: const Color(0xFF8D3DFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF8D3DFF),
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
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: const Color(0xFFECE9F6)),
        ),
        child: Icon(icon, color: const Color(0xFF6B4EFF)),
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

class _ShortcutChipData {
  const _ShortcutChipData({
    required this.title,
    required this.icon,
    required this.route,
    required this.tint,
  });

  final String title;
  final IconData icon;
  final String route;
  final Color tint;
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
