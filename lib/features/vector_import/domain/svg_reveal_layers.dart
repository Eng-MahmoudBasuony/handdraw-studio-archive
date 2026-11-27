import 'dart:ui';

/// Raster sources isolated by SVG paint role.
///
/// Keeping filled artwork and linework separate prevents a wide hand mask for
/// one element from revealing neighboring SVG pixels that belong to another
/// element. The complete artwork remains the source for text and final frames.
class SvgRevealLayers {
  const SvgRevealLayers({
    required this.fills,
    required this.strokes,
    this.globalStrokes,
  });

  final Image fills;
  final Image strokes;
  final Image? globalStrokes;

  void dispose() {
    fills.dispose();
    strokes.dispose();
    globalStrokes?.dispose();
  }
}
