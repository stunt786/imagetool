import 'package:flutter/material.dart';

/// Contextual action shown in a [SelectionActionBar].
class SelectionAction {
  const SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
}

/// Bottom action bar shown while items are selected.
///
/// Styled like the `prev1.jpg` reference: a dark bar with icon + label
/// actions, and a destructive action tinted for clarity.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.actions,
    this.count,
  });

  final List<SelectionAction> actions;

  /// Optional selection counter shown above the actions on wide layouts.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final action in actions)
              _SelectionActionButton(
                action: action,
                foreground: scheme.onInverseSurface,
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.action,
    required this.foreground,
  });

  final SelectionAction action;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final color = !enabled
        ? foreground.withValues(alpha: 0.4)
        : action.destructive
            ? const Color(0xFFFF8A80)
            : foreground;

    return Expanded(
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
