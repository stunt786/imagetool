import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/banner_ad_widget.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isMainScreen = currentPath == '/tools' ||
        currentPath == '/camera' ||
        currentPath == '/pdfs' ||
        currentPath == '/settings';
    final isCameraScreen = currentPath == '/camera';

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: navigationShell,
      bottomNavigationBar: isMainScreen
          ? SafeArea(
              minimum: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isCameraScreen) const BannerAdWidget(),
                  _BottomNavBar(navigationShell: navigationShell),
                ],
              ),
            )
          : null,
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final destinations = [
      _NavItemData(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      _NavItemData(
        label: 'Camera',
        icon: Icons.camera_alt_outlined,
        selectedIcon: Icons.camera_alt_rounded,
      ),
      _NavItemData(
        label: 'Files',
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder_rounded,
      ),
      _NavItemData(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(destinations.length, (index) {
          final item = destinations[index];
          final selected = navigationShell.currentIndex == index;
          return _NavItem(
            data: item,
            selected: selected,
            onTap: () => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? data.selectedIcon : data.icon,
              size: 22,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                data.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
