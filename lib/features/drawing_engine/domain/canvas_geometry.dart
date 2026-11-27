import 'dart:ui';

abstract final class CanvasGeometry {
  /// Fits [contentSize] completely inside [viewportSize] without distortion.
  ///
  /// Keeping this calculation independent from Flutter widgets makes the same
  /// geometry reusable by the editor, hit testing, and future viewport tools.
  static Rect contain({required Size viewportSize, Size? contentSize}) {
    final viewport = Offset.zero & viewportSize;
    if (contentSize == null ||
        contentSize.width <= 0 ||
        contentSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return viewport;
    }

    final contentRatio = contentSize.width / contentSize.height;
    final viewportRatio = viewportSize.width / viewportSize.height;
    if (contentRatio > viewportRatio) {
      final height = viewportSize.width / contentRatio;
      return Rect.fromLTWH(
        0,
        (viewportSize.height - height) / 2,
        viewportSize.width,
        height,
      );
    }

    final width = viewportSize.height * contentRatio;
    return Rect.fromLTWH(
      (viewportSize.width - width) / 2,
      0,
      width,
      viewportSize.height,
    );
  }
}
