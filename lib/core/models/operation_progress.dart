import 'package:flutter/foundation.dart';

/// Lifecycle of a long-running user-visible operation.
enum OperationStatus {
  idle,
  preparing,
  running,
  completed,
  failed,
  cancelled,
}

/// Immutable snapshot of a long-running operation's progress.
///
/// This is the single progress model used across the app so that every
/// feature reports work in the same shape and the UI can render it with one
/// reusable widget.
@immutable
class OperationProgress {
  const OperationProgress({
    this.operationId = '',
    this.title = '',
    this.statusText = '',
    this.status = OperationStatus.idle,
    this.completed = 0,
    this.total = 0,
    this.isIndeterminate = true,
    this.canCancel = false,
    this.errorMessage,
  });

  /// Neutral starting state.
  static const OperationProgress idle = OperationProgress();

  /// Stable identifier for the operation run (usually a timestamp token).
  final String operationId;

  /// Short headline, e.g. `Loading images`.
  final String title;

  /// Detail line, e.g. `Loading image 3 of 9`.
  final String statusText;

  final OperationStatus status;

  /// Number of work units finished.
  final int completed;

  /// Total work units, or 0 when unknown.
  final int total;

  /// True when the duration cannot be estimated (show a spinner, never a
  /// fake percentage).
  final bool isIndeterminate;

  final bool canCancel;

  final String? errorMessage;

  bool get isActive =>
      status == OperationStatus.preparing || status == OperationStatus.running;

  bool get isFinished =>
      status == OperationStatus.completed ||
      status == OperationStatus.failed ||
      status == OperationStatus.cancelled;

  /// Real progress in the `0.0..1.0` range, or null when it cannot be known.
  double? get fraction {
    if (isIndeterminate || total <= 0) return null;
    final value = completed / total;
    if (value.isNaN || !value.isFinite) return null;
    return value.clamp(0.0, 1.0);
  }

  int? get percent {
    final value = fraction;
    return value == null ? null : (value * 100).round();
  }

  /// `3 of 9` style counter, or null when there is no meaningful total.
  String? get counterLabel => total > 0 ? '$completed of $total' : null;

  OperationProgress copyWith({
    String? operationId,
    String? title,
    String? statusText,
    OperationStatus? status,
    int? completed,
    int? total,
    bool? isIndeterminate,
    bool? canCancel,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OperationProgress(
      operationId: operationId ?? this.operationId,
      title: title ?? this.title,
      statusText: statusText ?? this.statusText,
      status: status ?? this.status,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      isIndeterminate: isIndeterminate ?? this.isIndeterminate,
      canCancel: canCancel ?? this.canCancel,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'OperationProgress($status, $completed/$total, "$statusText")';
}
