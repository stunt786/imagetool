import 'package:flutter/foundation.dart';

import '../models/operation_progress.dart';

/// Thrown by cooperative workers when the user cancels an operation.
class OperationCancelledException implements Exception {
  const OperationCancelledException([this.message = 'Operation cancelled']);

  final String message;

  @override
  String toString() => message;
}

/// Drives [OperationProgress] for one long-running operation and provides
/// cooperative cancellation.
///
/// Usage:
/// ```dart
/// final controller = OperationProgressController();
/// controller.start(title: 'Converting images', total: images.length, canCancel: true);
/// for (final image in images) {
///   controller.throwIfCancelled();
///   await doWork(image);
///   controller.step(statusText: 'Converted ${image.name}');
/// }
/// controller.complete();
/// ```
///
/// Progress updates are throttled so that a tight loop over hundreds of items
/// cannot flood the UI with rebuilds, while status-text changes and terminal
/// states are always delivered immediately.
class OperationProgressController extends ChangeNotifier {
  OperationProgressController({
    this.throttle = const Duration(milliseconds: 80),
  });

  /// Minimum interval between progress notifications.
  final Duration throttle;

  OperationProgress _progress = OperationProgress.idle;
  bool _cancelled = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  OperationProgress get progress => _progress;

  bool get isCancelled => _cancelled;

  bool get isActive => _progress.isActive;

  /// Starts a new run. Any previous cancellation is cleared.
  void start({
    required String title,
    int total = 0,
    String statusText = 'Preparing...',
    bool canCancel = false,
    bool indeterminate = false,
  }) {
    _cancelled = false;
    _progress = OperationProgress(
      operationId: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      statusText: statusText,
      status: OperationStatus.preparing,
      total: total,
      isIndeterminate: indeterminate || total <= 0,
      canCancel: canCancel,
    );
    _forceNotify();
  }

  /// Moves to the running state (keeps the current counters).
  void begin({String? statusText}) {
    _progress = _progress.copyWith(
      status: OperationStatus.running,
      statusText: statusText ?? _progress.statusText,
      isIndeterminate: _progress.total <= 0,
    );
    _forceNotify();
  }

  /// Absolute progress update.
  void update({
    int? completed,
    int? total,
    String? statusText,
    bool? isIndeterminate,
    bool? canCancel,
  }) {
    _progress = _progress.copyWith(
      completed: completed,
      total: total,
      statusText: statusText,
      isIndeterminate: isIndeterminate,
      canCancel: canCancel,
      status: _progress.status == OperationStatus.preparing
          ? OperationStatus.running
          : _progress.status,
    );
    _maybeNotify(statusText != null);
  }

  /// Advances the counter and optionally replaces the detail line.
  void step({
    int by = 1,
    String? statusText,
    int? total,
    bool? isIndeterminate,
  }) {
    _progress = _progress.copyWith(
      completed: _progress.completed + by,
      total: total,
      statusText: statusText,
      isIndeterminate: isIndeterminate,
      status: _progress.status == OperationStatus.preparing
          ? OperationStatus.running
          : _progress.status,
    );
    _maybeNotify(statusText != null);
  }

  void complete([String? statusText]) {
    _progress = _progress.copyWith(
      status: OperationStatus.completed,
      statusText: statusText ?? 'Completed',
      completed: _progress.total > 0 ? _progress.total : _progress.completed,
      isIndeterminate: false,
      canCancel: false,
    );
    _forceNotify();
  }

  void fail([String? message]) {
    _progress = _progress.copyWith(
      status: OperationStatus.failed,
      statusText: message ?? 'Failed',
      errorMessage: message,
      canCancel: false,
    );
    _forceNotify();
  }

  /// Marks the run as cancelled. Workers must observe [isCancelled] (or call
  /// [throwIfCancelled]) to stop.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _progress = _progress.copyWith(
      status: OperationStatus.cancelled,
      statusText: 'Cancelled',
      canCancel: false,
    );
    _forceNotify();
  }

  /// Throws [OperationCancelledException] when the user cancelled, so callers
  /// can unwind and clean up without duplicating the check.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelledException();
  }

  /// Returns to the idle state after a terminal state has been shown.
  void reset() {
    _cancelled = false;
    _progress = OperationProgress.idle;
    _forceNotify();
  }

  void _maybeNotify(bool urgent) {
    final now = DateTime.now();
    if (!urgent && now.difference(_lastNotify) < throttle) return;
    _forceNotify();
  }

  void _forceNotify() {
    _lastNotify = DateTime.now();
    notifyListeners();
  }
}
