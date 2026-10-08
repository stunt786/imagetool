import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../camera/presentation/camera_screen.dart';
import '../../onboarding/presentation/feature_highlight_overlay.dart';
import 'shell_index_scope.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  Widget _buildScaffold(
    BuildContext context, {
    required bool isMainScreen,
    Key? cameraKey,
    Key? filesKey,
    VoidCallback? onCameraTap,
  }) {
    return Scaffold(
      extendBody: isMainScreen,
      extendBodyBehindAppBar: isMainScreen,
      // Branch screens stay mounted in the shell's IndexedStack, so this is
      // the only place they can observe which branch is active.
      body: ShellIndexScope(
        index: navigationShell.currentIndex,
        child: navigationShell,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        bottom: false,
        minimum: EdgeInsets.zero,
        child: _BottomNavBar(
          navigationShell: navigationShell,
          cameraKey: cameraKey,
          filesKey: filesKey,
          onCameraTap: onCameraTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isMainScreen = currentPath == '/tools' ||
        currentPath == '/camera' ||
        currentPath == '/pdfs';

    final hasScope = context.getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>() != null;
    if (!hasScope) {
      return _buildScaffold(
        context,
        isMainScreen: isMainScreen,
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final hasCompletedOnboarding = ref.watch(
            appSettingsProvider.select((s) => s.hasCompletedOnboarding));
        final keys = ref.watch(featureHighlightKeysProvider);

        final scaffold = _buildScaffold(
          context,
          isMainScreen: isMainScreen,
          cameraKey: (hasCompletedOnboarding || !(ModalRoute.of(context)?.isCurrent ?? true)) ? null : keys.cameraKey,
          filesKey: (hasCompletedOnboarding || !(ModalRoute.of(context)?.isCurrent ?? true)) ? null : keys.filesKey,
          onCameraTap: () {
            ref.read(cameraLaunchTriggerProvider.notifier).state++;
            navigationShell.goBranch(1, initialLocation: true);
          },
        );

        if (hasCompletedOnboarding) {
          return scaffold;
        }

        return FeatureHighlightOverlay(child: scaffold);
      },
    );
  }
}

/// Total content height of the bottom navigation bar (excludes the device's
/// bottom safe-area inset, which is painted opaquely behind the bar).
const double kBottomNavBarHeight = 72.0;

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.navigationShell,
    this.cameraKey,
    this.filesKey,
    this.onCameraTap,
  });

  final StatefulNavigationShell navigationShell;
  final Key? cameraKey;
  final Key? filesKey;
  final VoidCallback? onCameraTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // Fully opaque backdrop that matches the bottom of the bar gradient, so
    // scrolling content is never visible behind the menu (including the
    // safe-area strip below it).
    final backdropColor =
        isDark ? const Color(0xFFE6EDF5) : const Color(0xFFF5F8FC);

    return ColoredBox(
      color: backdropColor,
      child: Padding(
        padding: EdgeInsets.only(bottom: math.max(10.0, bottomPadding)),
        child: SizedBox(
          height: kBottomNavBarHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Flat, edge-to-edge bar background (no rounded corners)
              Positioned.fill(
                child: CustomPaint(
                  painter: _FlatBarPainter(isDark: isDark, scheme: scheme),
                ),
              ),

              // 2. Home · Camera · Files
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _NavItem(
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
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _CameraCenterButton(
                          key: cameraKey,
                          selected: currentIndex == 1,
                          diameter: 56,
                          onTap: () {
                            if (onCameraTap != null) {
                              onCameraTap!();
                            } else {
                              navigationShell
                                  .goBranch(1, initialLocation: true);
                            }
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _NavItem(
                          key: filesKey,
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

class _CameraCenterButton extends StatelessWidget {
  const _CameraCenterButton({
    super.key,
    required this.selected,
    required this.onTap,
    this.diameter = 56.0,
  });

  final bool selected;
  final VoidCallback onTap;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final buttonGradient = selected
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFFFFFFFF), Color(0xFFEDF2F7)]
                : const [Colors.white, Color(0xFFF1F5F9)],
          );

    final borderColor = selected
        ? Colors.white.withValues(alpha: 0.80)
        : const Color(0xFF1A73E8).withValues(alpha: 0.35);

    final iconColor = selected ? Colors.white : const Color(0xFF1A73E8);

    return Semantics(
      button: true,
      label: 'Camera',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: buttonGradient,
              border: Border.all(
                color: borderColor,
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? const Color(0xFF2563EB).withValues(alpha: 0.45)
                      : (isDark
                          ? Colors.black.withValues(alpha: 0.20)
                          : Colors.black.withValues(alpha: 0.10)),
                  blurRadius: selected ? 14 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: _CameraScannerIcon(
                size: 28,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraScannerIcon extends StatelessWidget {
  const _CameraScannerIcon({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(right: size * 0.10, bottom: size * 0.08),
            child: Icon(
              Icons.camera_alt_outlined,
              size: size * 0.82,
              color: color,
            ),
          ),
          Positioned(
            right: size * 0.02,
            bottom: size * 0.02,
            child: CustomPaint(
              size: Size(size * 0.38, size * 0.38),
              painter: _ReticlePainter(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final arm = w * 0.35;

    // Top-right bracket
    canvas.drawLine(Offset(w - arm, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, arm), paint);

    // Bottom-left bracket
    canvas.drawLine(Offset(0, h - arm), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(arm, h), paint);

    // Bottom-right bracket
    canvas.drawLine(Offset(w - arm, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h - arm), Offset(w, h), paint);

    // Center cross
    final cx = w * 0.48;
    final cy = h * 0.48;
    final cross = w * 0.18;
    canvas.drawLine(Offset(cx - cross, cy), Offset(cx + cross, cy), paint);
    canvas.drawLine(Offset(cx, cy - cross), Offset(cx, cy + cross), paint);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const activeColor = Color(0xFF1A73E8);
    final inactiveColor =
        isDark ? const Color(0xFF5A6679) : const Color(0xFF64748B);

    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected
                  ? const Color(0xFF1A73E8).withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: selected ? 1.08 : 1.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? selectedIcon : icon,
                    size: 26,
                    color: selected ? activeColor : inactiveColor,
                  ),
                  const SizedBox(height: 3),
                  // Label for screen readers / accessibility only: the parent
                  // Semantics node already carries this label, so keep the
                  // Text out of the semantics tree to avoid duplicates.
                  ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        letterSpacing: -0.1,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? activeColor : inactiveColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat, edge-to-edge background for the bottom menu: fully opaque so scrolled
/// content never shows through, with square (non-rounded) corners and a
/// hairline top separator.
class _FlatBarPainter extends CustomPainter {
  const _FlatBarPainter({
    required this.isDark,
    required this.scheme,
  });

  final bool isDark;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Opaque surface fill for the entire bar area
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        isDark
            ? const [
                Color(0xFFF3F6FA),
                Color(0xFFE6EDF5),
              ]
            : const [
                Colors.white,
                Color(0xFFF5F8FC),
              ],
      );
    canvas.drawRect(rect, fillPaint);

    // 2. Subtle separation from the scrolling content above
    final shadePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, 10),
        [
          Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
          Colors.transparent,
        ],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 10), shadePaint);

    // 3. Hairline top border
    final borderPaint = Paint()
      ..strokeWidth = 1.0
      ..color = isDark
          ? const Color(0xFFCBD5E1).withValues(alpha: 0.75)
          : scheme.outlineVariant.withValues(alpha: 0.70);
    canvas.drawLine(Offset(0, 0.5), Offset(size.width, 0.5), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FlatBarPainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.scheme != scheme;
  }
}
