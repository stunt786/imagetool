import 'package:flutter/widgets.dart';

/// Decode budget for an image drawn into a box of [logicalWidth] logical px.
///
/// Returns the width the bitmap should be decoded at for the current screen
/// density, so a 12 MP source renders into a 48 px thumbnail as a ~96 px
/// bitmap instead of a ~48 MB one. Only the width is returned: passing both
/// width and height to `Image` uses [ResizeImagePolicy.exact], which would
/// distort the aspect ratio before `BoxFit.cover` ever runs.
int decodeWidthFor(BuildContext context, double logicalWidth) {
  final ratio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3.0;
  final width = (logicalWidth * ratio).ceil();
  return width > 0 ? width : 1;
}

/// Decode budget for a full-bleed preview that the user can pinch to zoom.
///
/// [screenMultiple] of the screen width leaves headroom for zooming without
/// decoding the source at its native resolution: at 2x a 12 MP photo decodes
/// to roughly 18 MB instead of 48 MB, while staying sharp to about 2x zoom.
int zoomDecodeWidthFor(BuildContext context, {double screenMultiple = 2}) {
  final size = MediaQuery.maybeOf(context)?.size;
  final logicalWidth = size == null ? 480.0 : size.width * screenMultiple;
  return decodeWidthFor(context, logicalWidth);
}
