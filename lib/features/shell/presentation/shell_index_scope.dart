import 'package:flutter/widgets.dart';

/// Publishes the currently selected [StatefulShellRoute] branch index.
///
/// The shell keeps every branch alive in an `IndexedStack`, so screens in a
/// background branch stay mounted but never rebuild when the user switches
/// tabs — and `StatefulNavigationShell.of()` only walks the tree with
/// `findAncestorStateOfType`, which registers no inherited-widget dependency.
/// Descendants that must react to becoming visible therefore read this scope
/// from `didChangeDependencies` to get a notification on every tab change.
class ShellIndexScope extends InheritedWidget {
  const ShellIndexScope({
    super.key,
    required this.index,
    required super.child,
  });

  /// Index of the active branch, matching `StatefulNavigationShell.currentIndex`.
  final int index;

  /// Registers `context` as a dependent and returns the active branch index.
  ///
  /// Returns `null` when there is no shell above `context` (e.g. in a test
  /// that mounts a screen on its own).
  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellIndexScope>()?.index;

  @override
  bool updateShouldNotify(ShellIndexScope oldWidget) => index != oldWidget.index;
}
