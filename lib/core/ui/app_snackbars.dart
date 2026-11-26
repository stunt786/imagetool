import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presents operation results (success/failure messages) at the top-right
/// corner of the screen.
///
/// Every snackbar the app shows is routed through
/// [showTopSnackBar] so messages appear in the upper-right corner instead of
/// the default bottom position. The message itself stays a regular [SnackBar],
/// only the placement changes.
///
/// When the app-wide overlay is not available — for example inside a widget
/// test that builds a plain `MaterialApp` — messages fall back to the regular
/// bottom snackbar so nothing is lost.
class AppSnackbars extends StatefulWidget {
  const AppSnackbars({super.key, required this.child});

  /// The application content rendered underneath the messages.
  final Widget child;

  @override
  State<AppSnackbars> createState() => _AppSnackbarsState();
}

class _AppSnackbarsState extends State<AppSnackbars> {
  OverlayState? _overlay;

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (BuildContext context) {
            _overlay = Overlay.maybeOf(context);
            AppSnackbarsPresenter._attach(_overlay);
            return widget.child;
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    AppSnackbarsPresenter._detach(_overlay);
    super.dispose();
  }
}

/// Owns the overlay used to present messages and the currently visible one.
class AppSnackbarsPresenter {
  AppSnackbarsPresenter._();

  static OverlayState? _overlay;
  static _TopSnackHostState? _current;

  static void _attach(OverlayState? overlay) {
    if (overlay != null) {
      _overlay = overlay;
    }
  }

  static void _detach(OverlayState? overlay) {
    if (overlay == null || _overlay != overlay) {
      return;
    }
    // The overlay is going away with the subtree: only forget about the
    // message, removing the entry would race with the overlay teardown.
    _current?._abandon();
    _current = null;
    _overlay = null;
  }

  /// Shows [snackBar] at the top-right corner of [messenger]'s app.
  static AppSnackController show(
    ScaffoldMessengerState messenger,
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final OverlayState? overlay = _overlay;
    if (overlay == null || !overlay.mounted) {
      // No app overlay (plain MaterialApp, widget tests, …): bottom snackbar.
      return AppSnackController._fromScaffold(
        messenger.showSnackBar(
          snackBar,
          snackBarAnimationStyle: snackBarAnimationStyle,
        ),
      );
    }

    // A message already on screen is replaced, not queued.
    _current?._remove(SnackBarClosedReason.remove);
    _current = null;

    final AppSnackController controller = AppSnackController._top();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext context) => _TopSnackHost(
        snackBar: snackBar,
        entry: entry,
        controller: controller,
      ),
    );
    overlay.insert(entry);
    return controller;
  }

  /// Dismisses the message currently on screen, if any.
  ///
  /// Returns `true` when there was one, so callers can fall back to the
  /// regular messenger when the overlay is not in use.
  static bool dismiss(SnackBarClosedReason reason) {
    final _TopSnackHostState? current = _current;
    if (current == null) {
      return false;
    }
    current._dismiss(reason);
    return true;
  }

  /// Dismisses every message currently on screen.
  static void dismissAll() {
    dismiss(SnackBarClosedReason.remove);
  }
}

/// Handle for a message shown by [AppSnackbarsPresenter].
class AppSnackController {
  AppSnackController._fromScaffold(
    this._scaffoldController,
  ) : _completer = null;

  AppSnackController._top()
      : _scaffoldController = null,
        _completer = Completer<SnackBarClosedReason>();

  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
      _scaffoldController;
  final Completer<SnackBarClosedReason>? _completer;
  _TopSnackHostState? _host;

  /// Completes once the message is no longer on screen.
  Future<SnackBarClosedReason> get closed =>
      _scaffoldController?.closed ?? _completer!.future;

  /// Removes the message right away.
  void close() {
    final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
        scaffoldController = _scaffoldController;
    if (scaffoldController != null) {
      try {
        scaffoldController.close();
      } catch (_) {
        // Already gone.
      }
      return;
    }
    _host?._dismiss(SnackBarClosedReason.dismiss);
  }

  void _complete(SnackBarClosedReason reason) {
    final Completer<SnackBarClosedReason>? completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(reason);
    }
  }
}

extension TopRightSnackBars on ScaffoldMessengerState {
  /// Shows [snackBar] at the top-right corner of the screen.
  ///
  /// Drop-in replacement for [ScaffoldMessengerState.showSnackBar].
  AppSnackController showTopSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    return AppSnackbarsPresenter.show(
      this,
      snackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }

  /// Hides the message currently on screen, if any.
  ///
  /// Drop-in replacement for [ScaffoldMessengerState.hideCurrentSnackBar].
  void hideTopSnackBar(
      {SnackBarClosedReason reason = SnackBarClosedReason.hide}) {
    if (!AppSnackbarsPresenter.dismiss(reason)) {
      hideCurrentSnackBar(reason: reason);
    }
  }

  /// Removes every message currently on screen.
  ///
  /// Drop-in replacement for [ScaffoldMessengerState.clearSnackBars].
  void clearTopSnackBars() {
    AppSnackbarsPresenter.dismissAll();
    clearSnackBars();
  }
}

/// Renders one message in the top-right corner of the overlay.
class _TopSnackHost extends StatefulWidget {
  const _TopSnackHost({
    required this.snackBar,
    required this.entry,
    required this.controller,
  });

  final SnackBar snackBar;
  final OverlayEntry entry;
  final AppSnackController controller;

  @override
  State<_TopSnackHost> createState() => _TopSnackHostState();
}

class _TopSnackHostState extends State<_TopSnackHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final SnackBar _presented;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animation = SnackBar.createAnimationController(vsync: this);
    _presented = widget.snackBar.withAnimation(
      _animation,
      fallbackKey: const Key('top-right-snackbar'),
    );
    widget.controller._host = this;
    AppSnackbarsPresenter._current = this;
    _animation.forward().whenComplete(_onShown);
  }

  void _onShown() {
    if (!mounted || _closing || widget.snackBar.persist) {
      return;
    }
    _timer = Timer(widget.snackBar.duration, () {
      _dismiss(SnackBarClosedReason.timeout);
    });
  }

  /// Removes the message with the usual exit animation.
  void _dismiss(SnackBarClosedReason reason) {
    if (_closing || !mounted) {
      return;
    }
    _forget();
    _animation.reverse().whenComplete(() => _finish(reason));
  }

  /// Removes the message immediately, used when it is replaced by a new one.
  void _remove(SnackBarClosedReason reason) {
    if (_closing || !mounted) {
      return;
    }
    _forget();
    _animation.stop();
    _finish(reason);
  }

  /// The overlay hosting this message is being torn down.
  void _forget() {
    _closing = true;
    _timer?.cancel();
    if (identical(AppSnackbarsPresenter._current, this)) {
      AppSnackbarsPresenter._current = null;
    }
    widget.controller._host = null;
  }

  /// Forgets the message without animating it out because the overlay is
  /// going away, releasing anyone waiting on [AppSnackController.closed].
  void _abandon() {
    _forget();
    widget.controller._complete(SnackBarClosedReason.remove);
  }

  void _finish(SnackBarClosedReason reason) {
    if (widget.entry.mounted) {
      widget.entry.remove();
    }
    widget.controller._complete(reason);
  }

  @override
  void dispose() {
    _forget();
    widget.controller._complete(SnackBarClosedReason.remove);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // Sit just below the status bar so the message stays in the top-right
    // corner without being covered by system UI.
    final double topInset = math.max(media.viewPadding.top, media.padding.top);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: topInset + 12,
          left: 12,
          right: 12,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(400, media.size.width - 24),
          ),
          child: _TopSnackMessenger(
            onDismiss: _dismiss,
            child: _presented,
          ),
        ),
      ),
    );
  }
}

/// Messenger seen by the [SnackBar] itself.
///
/// [SnackBarAction], the close icon and swipe-to-dismiss all talk to
/// [ScaffoldMessenger] directly, so this nested messenger translates those
/// calls into dismissing the top-right message.
class _TopSnackMessenger extends ScaffoldMessenger {
  const _TopSnackMessenger({
    required this.onDismiss,
    required super.child,
  });

  final void Function(SnackBarClosedReason) onDismiss;

  @override
  ScaffoldMessengerState createState() => _TopSnackMessengerState();
}

class _TopSnackMessengerState extends ScaffoldMessengerState {
  @override
  _TopSnackMessenger get widget => super.widget as _TopSnackMessenger;

  @override
  void hideCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) {
    widget.onDismiss(reason);
    super.hideCurrentSnackBar(reason: reason);
  }

  @override
  void removeCurrentSnackBar({
    SnackBarClosedReason reason = SnackBarClosedReason.remove,
  }) {
    widget.onDismiss(reason);
    super.removeCurrentSnackBar(reason: reason);
  }
}
