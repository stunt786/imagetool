import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/banner_ad_widget.dart';
import '../../camera/presentation/camera_screen.dart';
import 'shell_index_scope.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isMainScreen = currentPath == '/tools' ||
        currentPath == '/camera' ||
        currentPath == '/pdfs';
    final isCameraScreen = currentPath == '/camera';

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      // Branch screens stay mounted in the shell's IndexedStack, so this is
      // the only place they can observe which branch is active.
      body: ShellIndexScope(
        index: navigationShell.currentIndex,
        child: navigationShell,
      ),
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

class _BottomNavBar extends ConsumerWidget {
  const _BottomNavBar({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0B101D).withValues(alpha: 0.95)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Home
          _NavItem(
            label: 'Home',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            selected: currentIndex == 0,
            onTap: () {
              navigationShell.goBranch(
                0,
                initialLocation: currentIndex == 0,
              );
            },
          ),
          // Camera in middle - larger size with curved border
          _CameraCenterButton(
            selected: currentIndex == 1,
            onTap: () {
              ref.read(cameraLaunchTriggerProvider.notifier).state++;
              navigationShell.goBranch(1, initialLocation: true);
            },
          ),
          // Files
          _NavItem(
            label: 'Files',
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder_rounded,
            selected: currentIndex == 2,
            onTap: () {
              if (navigationShell.route.branches.length > 2) {
                navigationShell.goBranch(
                  2,
                  initialLocation: currentIndex == 2,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _CameraCenterButton extends StatelessWidget {
  const _CameraCenterButton({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'Camera',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 58,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
                    )
                  : null,
              color: selected
                  ? null
                  : isDark
                      ? const Color(0xFF1E293B)
                      : scheme.primaryContainer.withValues(alpha: 0.45),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.5)
                    : scheme.primary.withValues(alpha: 0.7),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? const Color(0xFF2563EB).withValues(alpha: 0.4)
                      : scheme.shadow.withValues(alpha: 0.08),
                  blurRadius: selected ? 12 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                selected ? Icons.camera_alt_rounded : Icons.camera_alt_rounded,
                size: 28,
                color: selected ? Colors.white : scheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              selected ? selectedIcon : icon,
              size: 22,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                label,
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
