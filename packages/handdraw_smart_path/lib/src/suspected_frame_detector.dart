import 'dart:math' as math;
import 'dart:ui';

import 'models.dart';

final class SuspectedFrameAssessment {
  const SuspectedFrameAssessment({
    required this.isCandidate,
    required this.confidence,
  });

  const SuspectedFrameAssessment.none() : isCandidate = false, confidence = 0;

  final bool isCandidate;
  final double confidence;
}

/// Conservatively recognizes only an almost-full-canvas rectangular contour.
/// Inset cards, phones, underlines, and open three-sided shapes are rejected.
final class SuspectedFrameDetector {
  const SuspectedFrameDetector({
    this.maximumCanvasInset = 0.025,
    this.minimumCanvasSpan = 0.90,
    this.minimumBorderPointRatio = 0.82,
  });

  final double maximumCanvasInset;
  final double minimumCanvasSpan;
  final double minimumBorderPointRatio;

  SuspectedFrameAssessment assess(SmartPathSection section) {
    if (section.kind != SmartSectionKind.shape || section.paths.isEmpty) {
      return const SuspectedFrameAssessment.none();
    }
    final bounds = section.bounds;
    if (!_finiteRect(bounds) ||
        bounds.width < minimumCanvasSpan ||
        bounds.height < minimumCanvasSpan ||
        bounds.left > maximumCanvasInset ||
        bounds.top > maximumCanvasInset ||
        1 - bounds.right > maximumCanvasInset ||
        1 - bounds.bottom > maximumCanvasInset) {
      return const SuspectedFrameAssessment.none();
    }

    final borderBand = math.max(
      0.008,
      math.min(bounds.width, bounds.height) * 0.025,
    );
    final borderPaths = <List<Offset>>[];
    for (final path in section.paths) {
      final points = path.points
          .where((point) => point.dx.isFinite && point.dy.isFinite)
          .toList(growable: false);
      if (points.length < 2) continue;
      final borderPoints = points
          .where((point) => _isNearBorder(point, bounds, borderBand))
          .length;
      if (borderPoints / points.length >= minimumBorderPointRatio) {
        borderPaths.add(points);
      }
    }
    final points = borderPaths.expand((path) => path).toList(growable: false);
    if (points.length < 4) return const SuspectedFrameAssessment.none();

    var borderPoints = 0;
    var left = false;
    var right = false;
    var top = false;
    var bottom = false;
    var topLeft = false;
    var topRight = false;
    var bottomLeft = false;
    var bottomRight = false;
    for (final point in points) {
      final nearLeft = (point.dx - bounds.left).abs() <= borderBand;
      final nearRight = (point.dx - bounds.right).abs() <= borderBand;
      final nearTop = (point.dy - bounds.top).abs() <= borderBand;
      final nearBottom = (point.dy - bounds.bottom).abs() <= borderBand;
      if (nearLeft || nearRight || nearTop || nearBottom) borderPoints++;
      left |= nearLeft;
      right |= nearRight;
      top |= nearTop;
      bottom |= nearBottom;
      topLeft |= nearTop && nearLeft;
      topRight |= nearTop && nearRight;
      bottomLeft |= nearBottom && nearLeft;
      bottomRight |= nearBottom && nearRight;
    }
    final borderRatio = borderPoints / points.length;
    final hasAllSides = left && right && top && bottom;
    final hasAllCorners = topLeft && topRight && bottomLeft && bottomRight;
    if (!hasAllSides ||
        !hasAllCorners ||
        borderRatio < minimumBorderPointRatio) {
      return const SuspectedFrameAssessment.none();
    }

    final spanScore = math.min(
      1.0,
      math.min(bounds.width, bounds.height) / 0.94,
    );
    final borderScore = math.min(1.0, borderRatio / 0.90);
    final confidence = (0.97 + spanScore * 0.015 + borderScore * 0.015).clamp(
      0.0,
      0.999,
    );
    return SuspectedFrameAssessment(isCandidate: true, confidence: confidence);
  }
}

bool _isNearBorder(Offset point, Rect bounds, double band) =>
    (point.dx - bounds.left).abs() <= band ||
    (point.dx - bounds.right).abs() <= band ||
    (point.dy - bounds.top).abs() <= band ||
    (point.dy - bounds.bottom).abs() <= band;

bool _finiteRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;
