import 'package:flutter/material.dart';

import '../../../shared/widgets/banner_ad_widget.dart';

/// Wraps a screen's body content with a fixed bottom banner ad.
///
/// Use this for screens that are pushed outside the AppShell (tool sub-screens,
/// settings, etc.) where the shell-level banner is not visible.
///
/// Example:
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: Text('Tool')),
///   body: AdBannerWrapper(child: MyToolContent()),
/// )
/// ```
class AdBannerWrapper extends StatelessWidget {
  const AdBannerWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Scaffold gives its body loose width constraints, so without forcing
    // double.infinity this Column shrink-wraps to its widest child and the
    // whole screen sits flush left on tablets/landscape. Filling the width
    // lets each screen center its own content for any device size.
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Expanded(child: child),
          const Center(child: BannerAdWidget()),
        ],
      ),
    );
  }
}
