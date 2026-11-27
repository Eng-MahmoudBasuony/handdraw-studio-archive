import 'dart:math' as math;

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

/// Timing measured from the animation supplied as the product reference.
///
/// The 420 px-wide reference reveals 241 px of horizontal content in 1.00 s,
/// removes the hand over the following 0.42 s, and holds the completed artwork
/// for the remaining 3.99 s of its 5.41 s timeline. Durations scale with the
/// authored horizontal travel, so a wider section keeps the same apparent nib
/// speed instead of being stretched to fill the complete video duration.
final class ReferenceRevealMotionPolicy {
  const ReferenceRevealMotionPolicy();

  static const double sourceFrameRate = 12;
  static const double handExitSeconds = 0.42;
  static const double finalHoldSeconds = 3.99;
  static const double sectionTransitionSeconds = 1 / sourceFrameRate;
  static const double normalizedHorizontalSpeed = 241 / 420;

  double animationDurationSeconds(Iterable<DrawingStroke> strokes) {
    var horizontalTravel = 0.0;
    var fallbackTravel = 0.0;
    for (final stroke in strokes) {
      final points = stroke.orderedPoints;
      for (var index = 1; index < points.length; index++) {
        final delta = points[index] - points[index - 1];
        horizontalTravel += delta.dx.abs();
        fallbackTravel += delta.distance;
      }
    }
    final travel = horizontalTravel > 0.000001
        ? horizontalTravel
        : fallbackTravel;
    return math.max(1 / sourceFrameRate, travel / normalizedHorizontalSpeed);
  }

  Map<String, double> sectionAnimationDurations(
    Iterable<DrawingStroke> strokes,
  ) {
    final grouped = <String, List<DrawingStroke>>{};
    for (final stroke in strokes) {
      final sectionId = stroke.sectionId ?? 'manual-section-${stroke.id}';
      grouped.putIfAbsent(sectionId, () => []).add(stroke);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: animationDurationSeconds(entry.value),
    };
  }
}
