import 'package:flutter/material.dart';

import '../models/operation_progress.dart';
import 'operation_progress_controller.dart';

/// Inline progress card: title, status line, bar/spinner, counter and an
/// optional cancel action.
///
/// Deliberately overflow-safe: every text line is limited and ellipsised so it
/// stays usable on small phones, in landscape and with large font scaling.
class OperationProgressCard extends StatelessWidget {
  const OperationProgressCard({
    super.key,
    required this.progress,
    this.onCancel,
    this.dense = false,
    this.showTitle = true,
  });

  final OperationProgress progress;
  final VoidCallback? onCancel;
  final bool dense;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = progress.fraction;
    final isFailed = progress.status == OperationStatus.failed;
    final isCancelled = progress.status == OperationStatus.cancelled;
    final isCompleted = progress.status == OperationStatus.completed;

    final accent = isFailed
        ? scheme.error
        : isCancelled
            ? scheme.onSurfaceVariant
            : isCompleted
                ? scheme.secondary
                : scheme.primary;

    final icon = isFailed
        ? Icons.error_outline_rounded
        : isCancelled
            ? Icons.cancel_outlined
            : isCompleted
                ? Icons.check_circle_outline_rounded
                : Icons.sync_rounded;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle && progress.title.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: dense ? 16 : 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (dense
                          ? theme.textTheme.labelLarge
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        if (progress.statusText.isNotEmpty) ...[
          SizedBox(height: dense ? 4 : 8),
          Text(
            progress.statusText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: dense ? 6 : 12),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: dense ? 4 : 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ),
            if (progress.counterLabel != null) ...[
              const SizedBox(width: 12),
              Text(
                progress.counterLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        if (progress.errorMessage != null &&
            progress.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            progress.errorMessage!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Minimal bar + counter for tight spaces (bottom bars, list headers).
class OperationProgressBar extends StatelessWidget {
  const OperationProgressBar({super.key, required this.progress});

  final OperationProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress.fraction;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        if (progress.counterLabel != null) ...[
          const SizedBox(width: 10),
          Text(
            progress.counterLabel!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Modal, non-dismissible progress dialog bound to a controller.
///
/// The dialog closes itself as soon as the operation reaches a terminal state
/// (after a short delay so the user can read `Completed`/`Failed`). While the
/// operation is active the system back gesture requests cancellation when the
/// controller allows it.
class OperationProgressDialog extends StatelessWidget {
  const OperationProgressDialog({super.key, required this.controller});

  final OperationProgressController controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (controller.progress.canCancel) controller.cancel();
      },
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => OperationProgressCard(
              progress: controller.progress,
              onCancel: controller.progress.canCancel
                  ? controller.cancel
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [OperationProgressDialog] and keeps it in sync with [controller].
///
/// Returns a future that completes once the dialog is dismissed.
Future<void> showOperationProgressDialog({
  required BuildContext context,
  required OperationProgressController controller,
  bool autoClose = true,
  Duration autoCloseDelay = const Duration(milliseconds: 600),
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var dismissed = false;

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    if (navigator.mounted) navigator.pop();
  }

  void onProgress() {
    if (!autoClose) return;
    if (controller.progress.isFinished) {
      Future<void>.delayed(autoCloseDelay, dismiss);
    }
  }

  controller.addListener(onProgress);
  onProgress();

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => OperationProgressDialog(
        controller: controller,
      ),
    );
  } finally {
    controller.removeListener(onProgress);
  }
}
