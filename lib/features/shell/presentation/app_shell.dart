import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/banner_ad_widget.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const destinations = [
      _ShellDestination(
        label: 'Tools',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
      ),
      _ShellDestination(
        label: 'Camera',
        icon: Icons.camera_alt_outlined,
        selectedIcon: Icons.camera_alt_rounded,
      ),
      _ShellDestination(
        label: 'Images',
        icon: Icons.collections_outlined,
        selectedIcon: Icons.collections_rounded,
      ),
      _ShellDestination(
        label: 'PDFs',
        icon: Icons.picture_as_pdf_outlined,
        selectedIcon: Icons.picture_as_pdf_rounded,
      ),
    ];

    final currentPath = GoRouterState.of(context).uri.path;
    final isMainScreen = currentPath == '/tools' ||
        currentPath == '/camera' ||
        currentPath == '/images' ||
        currentPath == '/pdfs';

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: isMainScreen
          ? SafeArea(
              minimum: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google AdMob banner ad displayed above the navigation bar
                  const BannerAdWidget(),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest.withValues(alpha: 0.96),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.95),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(destinations.length, (index) {
                        final item = destinations[index];
                        final selected = navigationShell.currentIndex == index;

                        return _ShellNavItem(
                          destination: item,
                          selected: selected,
                          onTap: () => navigationShell.goBranch(
                            index,
                            initialLocation: index == navigationShell.currentIndex,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? Colors.white
              : scheme.surfaceContainerLow.withValues(alpha: 0.8),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: 24,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
