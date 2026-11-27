import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

/// Builds a diagonal sweep reveal for a raster whose pixels are all opaque.
///
/// The strokes are ordinary reveal-only brush strokes, so Preview and export
/// keep using the shared reveal compositor. Routing opaque rasters to this
/// planner is deliberately owned by the editor; SVG and alpha-bearing raster
/// artwork never need to change their established path-generation behavior.
class OpaqueRasterRevealPlanner {
  const OpaqueRasterRevealPlanner({
    this.diagonalRise = 0.16,
    this.normalizedBrushWidth = 0.18,
    this.normalizedStripeSpacing = 0.12,
  });

  final double diagonalRise;
  final double normalizedBrushWidth;
  final double normalizedStripeSpacing;

  List<DrawingStroke> build({required HandDrawProject project}) {
    final rise = diagonalRise.clamp(0.0, 0.25);
    final brushWidth = normalizedBrushWidth.clamp(0.04, 0.25);
    final spacing = math.min(
      normalizedStripeSpacing.clamp(0.03, 0.2),
      brushWidth * 0.9,
    );
    final radius = brushWidth / 2;
    // The diagonal sweep travels from top to bottom in visibly
    // diagonal strokes. Keep the calibrated pen tip inside the artwork while
    // the overlapping brush radius covers every opaque pixel without gaps.
    final firstIntercept = radius * 0.55;
    final lastIntercept = math.max(firstIntercept, 1 - radius * 0.55 - rise);
    final stripeCount = ((lastIntercept - firstIntercept) / spacing).ceil() + 1;
    final stripeStep = stripeCount <= 1
        ? 0.0
        : (lastIntercept - firstIntercept) / (stripeCount - 1);
    final generation = DateTime.now().microsecondsSinceEpoch;
    final points = <Offset>[];
    for (var index = 0; index < stripeCount; index++) {
      final intercept = firstIntercept + index * stripeStep;
      if (index.isEven) {
        points
          ..add(Offset(0, intercept))
          ..add(Offset(1, intercept + rise));
      } else {
        points
          ..add(Offset(1, intercept + rise))
          ..add(Offset(0, intercept));
      }
    }

    return List.unmodifiable([
      DrawingStroke(
        id: 'auto-opaque-reveal-$generation',
        name: 'Opaque Artwork • Diagonal Reveal',
        points: points,
        revealOnly: true,
        revealStyle: RevealMaskStyle.brush,
        sectionId: 'auto-opaque-raster-reveal',
        clipBounds: const Rect.fromLTWH(0, 0, 1, 1),
        revealWidth: project.canvasHeight * brushWidth,
      ),
    ]);
  }
}
