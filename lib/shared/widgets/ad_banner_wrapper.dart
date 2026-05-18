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
    return Column(
      children: [
        Expanded(child: child),
        const BannerAdWidget(),
      ],
    );
  }
}
