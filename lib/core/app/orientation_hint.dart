import 'package:flutter/material.dart';

/// Gentle nudge back to portrait when the app is rotated into landscape.
///
/// Nothing is forced: every orientation stays supported. Portrait is the
/// natural default (devices start there and `AppSystemUi.configure` does not
/// restrict the set), but most layouts are tuned for portrait, so a single
/// hint is shown each time the user rotates the app from portrait into
/// landscape. It fires once per rotation and is re-armed only by a return to
/// portrait, so it never spams the user while they stay in landscape — and an
/// app that simply starts out on an already-landscape device (tablet, desktop)
/// is never interrupted.
class OrientationHint extends StatefulWidget {
  const OrientationHint({super.key, required this.child});

  final Widget child;

  /// Text of the one-off hint.
  static const String message =
      'Portrait mode is recommended for easier navigation.';

  @override
  State<OrientationHint> createState() => _OrientationHintState();
}

class _OrientationHintState extends State<OrientationHint> {
  Orientation? _lastOrientation;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.maybeOf(context)?.orientation;
    if (orientation != null) {
      if (orientation == Orientation.landscape &&
          _lastOrientation == Orientation.portrait) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showHint());
      }
      _lastOrientation = orientation;
    }
    return widget.child;
  }

  void _showHint() {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(OrientationHint.message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }
}
