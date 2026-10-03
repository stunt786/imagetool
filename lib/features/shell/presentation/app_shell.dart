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
          cameraKey: keys.cameraKey,
          filesKey: keys.filesKey,
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

  static const double _barHeight = 84.0;
  static const double _topOffset = 26.0;
  static const double _circleCenterY = 28.0;
  static const double _buttonRadius = 28.0; // 56dp diameter circle
  static const double _gap = 7.0; // 35dp notch radius
  static const double _shoulderRadius = 14.0;
  static const double _cornerRadius = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        math.max(10.0, bottomPadding),
      ),
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cx = width / 2;

            // Compute notch clearance boundary
            final sy = _topOffset + _shoulderRadius;
            final dy = sy - _circleCenterY;
            final hyp = (_buttonRadius + _gap) + _shoulderRadius;
            final bx = math.sqrt(math.max(0.0, hyp * hyp - dy * dy));

            final leftWingWidth = cx - bx;
            final rightWingWidth = width - (cx + bx);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Notched scooped background bar
                Positioned.fill(
                  child: CustomPaint(
                    painter: _NotchedBarPainter(
                      isDark: isDark,
                      scheme: scheme,
                      topOffset: _topOffset,
                      circleCenterY: _circleCenterY,
                      buttonRadius: _buttonRadius,
                      gap: _gap,
                      shoulderRadius: _shoulderRadius,
                      cornerRadius: _cornerRadius,
                    ),
                  ),
                ),

                // 2. Home icon in left wing
                Positioned(
                  left: 0,
                  top: _topOffset,
                  width: leftWingWidth,
                  height: _barHeight - _topOffset,
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

                // 3. Center Camera floating circular button
                Positioned(
                  left: cx - _buttonRadius,
                  top: _circleCenterY - _buttonRadius,
                  child: _CameraCenterButton(
                    key: cameraKey,
                    selected: currentIndex == 1,
                    diameter: _buttonRadius * 2,
                    onTap: () {
                      if (onCameraTap != null) {
                        onCameraTap!();
                      } else {
                        navigationShell.goBranch(1, initialLocation: true);
                      }
                    },
                  ),
                ),

                // 4. Files icon in right wing
                Positioned(
                  left: cx + bx,
                  top: _topOffset,
                  width: rightWingWidth,
                  height: _barHeight - _topOffset,
                  child: Center(
                    child: _NavItem(
                      key: filesKey,
                      label: 'Files',
                      icon: Icons.snippet_folder_outlined,
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
            );
          },
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected
                  ? const Color(0xFF1A73E8).withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: selected ? 1.08 : 1.0,
              child: Icon(
                selected ? selectedIcon : icon,
                size: 26,
                color: selected ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotchedBarPainter extends CustomPainter {
  const _NotchedBarPainter({
    required this.isDark,
    required this.scheme,
    required this.topOffset,
    required this.circleCenterY,
    required this.buttonRadius,
    required this.gap,
    required this.shoulderRadius,
    required this.cornerRadius,
  });

  final bool isDark;
  final ColorScheme scheme;
  final double topOffset;
  final double circleCenterY;
  final double buttonRadius;
  final double gap;
  final double shoulderRadius;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildNotchedBarPath(
      width: size.width,
      height: size.height,
      topOffset: topOffset,
      circleCenterY: circleCenterY,
      buttonRadius: buttonRadius,
      gap: gap,
      shoulderRadius: shoulderRadius,
      cornerRadius: cornerRadius,
    );

    // 1. Soft elevation shadow
    canvas.drawShadow(
      path,
      isDark ? Colors.black.withValues(alpha: 0.35) : const Color(0x280F172A),
      10.0,
      false,
    );

    // 2. Bar background fill (clean light surface that matches both dark & light themes)
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, topOffset),
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
    canvas.drawPath(path, fillPaint);

    // 3. Crisp outline border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = isDark
          ? const Color(0xFFCBD5E1).withValues(alpha: 0.75)
          : scheme.outlineVariant.withValues(alpha: 0.70);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _NotchedBarPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.scheme != scheme ||
        oldDelegate.topOffset != topOffset ||
        oldDelegate.circleCenterY != circleCenterY ||
        oldDelegate.buttonRadius != buttonRadius ||
        oldDelegate.gap != gap ||
        oldDelegate.shoulderRadius != shoulderRadius ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

Path _buildNotchedBarPath({
  required double width,
  required double height,
  required double topOffset,
  required double circleCenterY,
  required double buttonRadius,
  required double gap,
  required double shoulderRadius,
  required double cornerRadius,
}) {
  final path = Path();
  final cx = width / 2;
  final cy = circleCenterY;
  final rNotch = buttonRadius + gap;
  final s = shoulderRadius;

  final sy = topOffset + s;
  final dy = sy - cy;
  final hyp = rNotch + s;
  final bx = math.sqrt(math.max(0.0, hyp * hyp - dy * dy));

  final sxLeft = cx - bx;
  final sxRight = cx + bx;

  final angleTangentLeft = math.atan2(-dy, bx);
  final angleTangentRight = math.atan2(-dy, -bx);

  final angStart = math.atan2(dy * rNotch / hyp, -bx * rNotch / hyp);
  final angEnd = math.atan2(dy * rNotch / hyp, bx * rNotch / hyp);

  // 1. Top-left corner
  path.moveTo(0, topOffset + cornerRadius);
  path.arcToPoint(
    Offset(cornerRadius, topOffset),
    radius: Radius.circular(cornerRadius),
    clockwise: true,
  );

  // 2. Line to left shoulder top
  path.lineTo(sxLeft, topOffset);

  // 3. Left shoulder arc: from -pi/2 to angleTangentLeft
  const steps = 14;
  for (int i = 1; i <= steps; i++) {
    final ang =
        -math.pi / 2 + (angleTangentLeft - (-math.pi / 2)) * (i / steps);
    path.lineTo(sxLeft + s * math.cos(ang), sy + s * math.sin(ang));
  }

  // 4. Notch cradle arc: from angStart to angEnd
  for (int i = 1; i <= steps * 2; i++) {
    final ang = angStart + (angEnd - angStart) * (i / (steps * 2));
    path.lineTo(cx + rNotch * math.cos(ang), cy + rNotch * math.sin(ang));
  }

  // 5. Right shoulder arc: from angleTangentRight to -pi/2
  for (int i = 1; i <= steps; i++) {
    final ang =
        angleTangentRight + (-math.pi / 2 - angleTangentRight) * (i / steps);
    path.lineTo(sxRight + s * math.cos(ang), sy + s * math.sin(ang));
  }

  // 6. Line to top-right corner
  path.lineTo(width - cornerRadius, topOffset);

  // 7. Top-right corner
  path.arcToPoint(
    Offset(width, topOffset + cornerRadius),
    radius: Radius.circular(cornerRadius),
    clockwise: true,
  );

  // 8. Line down right side
  path.lineTo(width, height - cornerRadius);

  // 9. Bottom-right corner
  path.arcToPoint(
    Offset(width - cornerRadius, height),
    radius: Radius.circular(cornerRadius),
    clockwise: true,
  );

  // 10. Line along bottom
  path.lineTo(cornerRadius, height);

  // 11. Bottom-left corner
  path.arcToPoint(
    Offset(0, height - cornerRadius),
    radius: Radius.circular(cornerRadius),
    clockwise: true,
  );

  path.close();
  return path;
}
