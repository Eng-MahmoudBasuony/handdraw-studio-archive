import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/auto_path/domain/services/reference_reveal_motion_policy.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

/// Converts confirmed scene masks into a small, deterministic reveal plan.
///
/// Scene splitting is an ordering tool, so it must not implicitly run dense
/// raster tracing. Each scene owns one gently drifting, monotonic writing
/// pass. Its directional mask accumulates behind the nib inside the authored
/// scene polygon and can never hide artwork that was already revealed.
final class SceneRegionRevealPlanner {
  const SceneRegionRevealPlanner({
    this.minimumBrushHeightFraction = 0.22,
    this.maximumBrushHeightFraction = 0.42,
    this.motionPolicy = const ReferenceRevealMotionPolicy(),
  });

  final double minimumBrushHeightFraction;
  final double maximumBrushHeightFraction;
  final ReferenceRevealMotionPolicy motionPolicy;

  SceneRegionRevealPlan build({
    required List<SceneRegion> regions,
    required double canvasHeight,
  }) {
    final entries = <SceneRegionRevealEntry>[];
    final generation = DateTime.now().microsecondsSinceEpoch;
    for (var index = 0; index < regions.length; index++) {
      final region = regions[index];
      final bounds = region.bounds.intersect(const Rect.fromLTWH(0, 0, 1, 1));
      final masks = region.maskPolygons;
      if (bounds.isEmpty || masks.isEmpty || canvasHeight <= 0) continue;

      final brushFraction = math
          .max(minimumBrushHeightFraction, bounds.height * 1.08)
          .clamp(minimumBrushHeightFraction, maximumBrushHeightFraction);
      const passCount = 1;
      final points = _writingPath(
        bounds,
        brushFraction,
        rightToLeft: index.isOdd,
      );
      final stroke = DrawingStroke(
        id: 'scene-reveal-$generation-$index',
        name: '${region.name} • Broad hand reveal',
        points: points,
        revealOnly: true,
        revealStyle: RevealMaskStyle.directionalWipe,
        sectionId: region.id,
        clipBounds: bounds,
        clipPolygons: masks,
        revealWidth: canvasHeight * brushFraction,
      );
      entries.add(
        SceneRegionRevealEntry(
          region: region,
          passCount: passCount,
          stroke: stroke,
          animationDurationSeconds: motionPolicy.animationDurationSeconds([
            stroke,
          ]),
        ),
      );
    }
    return SceneRegionRevealPlan(entries: entries);
  }

  List<Offset> _writingPath(
    Rect bounds,
    double brushFraction, {
    required bool rightToLeft,
  }) {
    final drift = math.min(bounds.height * 0.055, brushFraction * 0.08);
    final y = bounds.center.dy;
    final points = [
      Offset(bounds.left, (y + drift * 0.25).clamp(bounds.top, bounds.bottom)),
      Offset(
        bounds.left + bounds.width * 0.32,
        (y - drift).clamp(bounds.top, bounds.bottom),
      ),
      Offset(
        bounds.left + bounds.width * 0.68,
        (y + drift * 0.72).clamp(bounds.top, bounds.bottom),
      ),
      Offset(bounds.right, (y - drift * 0.18).clamp(bounds.top, bounds.bottom)),
    ];
    return List.unmodifiable(rightToLeft ? points.reversed : points);
  }
}

final class SceneRegionRevealPlan {
  SceneRegionRevealPlan({required List<SceneRegionRevealEntry> entries})
    : entries = List.unmodifiable(entries);

  final List<SceneRegionRevealEntry> entries;

  List<DrawingStroke> get strokes =>
      List.unmodifiable([for (final entry in entries) entry.stroke]);
}

final class SceneRegionRevealEntry {
  const SceneRegionRevealEntry({
    required this.region,
    required this.stroke,
    required this.passCount,
    required this.animationDurationSeconds,
  });

  final SceneRegion region;
  final DrawingStroke stroke;
  final int passCount;
  final double animationDurationSeconds;
}
