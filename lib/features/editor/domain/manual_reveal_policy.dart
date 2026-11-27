import 'dart:math' as math;

/// Keeps manual reveal strokes broad enough to uncover a complete title line
/// with one authored gesture, without changing Auto Path's global brush size.
final class ManualRevealPolicy {
  const ManualRevealPolicy();

  static const double minimumCanvasHeightFraction = 0.22;
  static const double maximumWidth = 960;

  double resolve({
    required double projectRevealWidth,
    required double canvasHeight,
    double? authoredWidth,
  }) {
    if (authoredWidth != null) {
      return authoredWidth.clamp(4.0, maximumWidth);
    }
    return math
        .max(projectRevealWidth, canvasHeight * minimumCanvasHeightFraction)
        .clamp(4.0, maximumWidth);
  }
}
