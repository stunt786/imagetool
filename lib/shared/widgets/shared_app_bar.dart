import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SharedAppBar({
    super.key,
    required this.drawerKey,
    this.title,
  });

  final GlobalKey<ScaffoldState> drawerKey;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72,
      centerTitle: true,
      flexibleSpace: const _TopBarBackground(),
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
        child: Builder(
          builder: (context) => _GlassIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            embedded: true,
            onTap: () => drawerKey.currentState?.openDrawer(),
          ),
        ),
      ),
      title: title != null
          ? Text(
              title!,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            )
          : const _BrandTitle(),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 18, top: 6, bottom: 6),
          child: _TopBarSpacer(),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(72);
}

class SharedAppDrawer extends StatelessWidget {
  const SharedAppDrawer({
    super.key,
    required this.outputFolder,
    required this.watermarkText,
    required this.keepExifData,
    // required this.onUpgradeTap, // TODO: Re-enable in upcoming version with premium features
    required this.onSettingsTap,
    required this.onOutputFolderTap,
    required this.onWatermarkTap,
    required this.onKeepExifChanged,
    required this.onHelpTap,
    required this.onContactTap,
    required this.onShareTap,
  });

  final String outputFolder;
  final String watermarkText;
  final bool keepExifData;
  // final VoidCallback onUpgradeTap; // TODO: Re-enable in upcoming version with premium features
  final VoidCallback onSettingsTap;
  final VoidCallback onOutputFolderTap;
  final VoidCallback onWatermarkTap;
  final ValueChanged<bool> onKeepExifChanged;
  final VoidCallback onHelpTap;
  final VoidCallback onContactTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Drawer(
      width: 320,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF181A35), Color(0xFF2B3E7E)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandTitle(),
                      const SizedBox(height: 10),
                      Text(
                        'Control exports, watermarking, privacy, and support from one place.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  children: [
                    // TODO: Re-enable premium upgrade tile in upcoming version with premium features
                    // _DrawerTile(
                    //   icon: Icons.workspace_premium_rounded,
                    //   title: 'Upgrade to Premium',
                    //   subtitle: 'Unlock advanced exports and pro workflows',
                    //   accent: const Color(0xFF7C3AED),
                    //   onTap: onUpgradeTap,
                    // ),
                    const SizedBox(height: 8),
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          12,
                        ),
                        backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
                        collapsedBackgroundColor: scheme.surfaceContainerLowest.withValues(
                          alpha: 0.82,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        leading: Icon(
                          Icons.settings_rounded,
                          color: scheme.primary,
                        ),
                        title: Text(
                          'Settings',
                          style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface),
                        ),
                        subtitle: Text('Folders, watermark, metadata', style: TextStyle(color: scheme.onSurfaceVariant)),
                        children: [
                          _MiniDrawerTile(
                            title: 'Change output folder',
                            subtitle: outputFolder,
                            onTap: onOutputFolderTap,
                          ),
                          _MiniDrawerTile(
                            title: 'Custom text watermark',
                            subtitle: watermarkText,
                            onTap: onWatermarkTap,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: keepExifData,
                            activeTrackColor: scheme.primary,
                            title: Text('Keep EXIF data', style: TextStyle(color: scheme.onSurface)),
                            subtitle: Text('Preserve original metadata', style: TextStyle(color: scheme.onSurfaceVariant)),
                            onChanged: onKeepExifChanged,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: onSettingsTap,
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Open full settings'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DrawerTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help',
                      subtitle: 'Learn how the app works',
                      accent: const Color(0xFF0EA5A4),
                      onTap: onHelpTap,
                    ),
                    const SizedBox(height: 8),
                    _DrawerTile(
                      icon: Icons.mail_outline_rounded,
                      title: 'Contact Us',
                      subtitle: 'Share feedback and bug reports',
                      accent: const Color(0xFFEA580C),
                      onTap: onContactTap,
                    ),
                    const SizedBox(height: 8),
                    _DrawerTile(
                      icon: Icons.ios_share_rounded,
                      title: 'Share App',
                      subtitle: 'Invite others to try PixelTools',
                      accent: const Color(0xFF15803D),
                      onTap: onShareTap,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'App version v1.0.0+1',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.7,
          color: Colors.white,
        );

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF1F2A44), Color(0xFF5B4DFF), Color(0xFF0EA5A4)],
      ).createShader(bounds),
      child: Text(
        AppStrings.appName,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

class _TopBarBackground extends StatelessWidget {
  const _TopBarBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarSpacer extends StatelessWidget {
  const _TopBarSpacer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 48, height: 48);
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
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

class _MiniDrawerTile extends StatelessWidget {
  const _MiniDrawerTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.embedded = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: embedded
                ? Colors.transparent
                : scheme.surfaceContainerLow.withValues(alpha: 0.92),
            border: embedded
                ? null
                : Border.all(color: scheme.outlineVariant),
            boxShadow: embedded
                ? null
                : [
                    BoxShadow(
                      color: scheme.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Icon(icon, color: scheme.onSurface),
        ),
      ),
    );
  }
}
