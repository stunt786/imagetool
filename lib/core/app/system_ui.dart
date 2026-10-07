import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'orientation_hint.dart';

/// App level system UI configuration: allowed orientations, edge-to-edge
/// rendering and the status/navigation bar icon contrast.
abstract final class AppSystemUi {
  /// Every orientation is supported. Portrait stays the default because the
  /// platform starts there (and no lock restricts the set), while landscape
  /// remains usable — [OrientationHint] simply suggests going back.
  static const List<DeviceOrientation> allOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// Allows every orientation (portrait by default) and lets the app draw
  /// behind the system bars (edge-to-edge).
  static Future<void> configure() async {
    await SystemChrome.setPreferredOrientations(allOrientations);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    const transparent = Color(0x00000000);
    return SystemUiOverlayStyle(
      statusBarColor: transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: transparent,
      systemNavigationBarDividerColor: transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// `MaterialApp.builder` shared by both the splash and the main app: keeps
  /// the system bars transparent/readable and nudges the user back to portrait
  /// when they rotate into landscape.
  static TransitionBuilder appBuilder(TransitionBuilder? baseBuilder) {
    return (BuildContext context, Widget? child) {
      final Widget? content = baseBuilder?.call(context, child) ?? child;
      return OrientationHint(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle(Theme.of(context).brightness),
          child: content ?? const SizedBox.shrink(),
        ),
      );
    };
  }
}
