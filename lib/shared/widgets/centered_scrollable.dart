import 'package:flutter/material.dart';

/// Lays out [child] centered in the available space, but allows it to scroll
/// when the viewport is shorter than the content (small screens, landscape,
/// large text scale). This avoids `RenderFlex overflowed ... on the bottom`
/// errors on constrained devices.
class CenteredScrollable extends StatelessWidget {
  const CenteredScrollable({
    super.key,
    required this.child,
    this.physics,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        final minWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
        return SingleChildScrollView(
          physics: physics,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minHeight,
              minWidth: minWidth,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Center(
                child: IntrinsicHeight(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
