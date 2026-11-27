import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';

/// One output-space contract for hand painting and pen-tip diagnostics.
final class HandDisplayTransform {
  const HandDisplayTransform({
    required this.layout,
    required this.projectedPathPoint,
    required this.rotationRadians,
    required this.flipX,
  });

  final HandDisplayLayout layout;
  final Offset projectedPathPoint;
  final double rotationRadians;
  final bool flipX;

  Offset get scaledPenAnchor => Offset(layout.penAnchorX, layout.penAnchorY);

  /// Pen-tip location in the untransformed source image. The layout stores the
  /// post-flip anchor so mirrored hands still rotate around the visible nib.
  Offset get sourcePenAnchor => Offset(
    flipX ? layout.width - layout.penAnchorX : layout.penAnchorX,
    layout.penAnchorY,
  );

  /// The transform rotates and flips around the pen anchor, therefore this
  /// must equal [projectedPathPoint] independently of scale or rotation.
  Offset get displayedPenTip => projectSourcePoint(sourcePenAnchor);

  Rect get unrotatedImageBounds => Rect.fromLTWH(
    projectedPathPoint.dx - scaledPenAnchor.dx,
    projectedPathPoint.dy - scaledPenAnchor.dy,
    layout.width,
    layout.height,
  );

  List<Offset> get projectedFootprint {
    return [
      projectSourcePoint(Offset.zero),
      projectSourcePoint(Offset(layout.width, 0)),
      projectSourcePoint(Offset(layout.width, layout.height)),
      projectSourcePoint(Offset(0, layout.height)),
    ];
  }

  Offset projectSourcePoint(Offset source) {
    final anchor = scaledPenAnchor;
    final cosine = math.cos(rotationRadians);
    final sine = math.sin(rotationRadians);
    final flipped = flipX
        ? Offset(layout.width - source.dx, source.dy)
        : source;
    final local = flipped - anchor;
    return projectedPathPoint +
        Offset(
          local.dx * cosine - local.dy * sine,
          local.dx * sine + local.dy * cosine,
        );
  }

  void apply(Canvas canvas) {
    canvas.translate(projectedPathPoint.dx, projectedPathPoint.dy);
    canvas.rotate(rotationRadians);
    canvas.translate(-scaledPenAnchor.dx, -scaledPenAnchor.dy);
    if (flipX) {
      canvas.translate(layout.width, 0);
      canvas.scale(-1, 1);
    }
  }
}

final class HandAlignmentDiagnostic {
  const HandAlignmentDiagnostic({
    required this.activeWorldPathPoint,
    required this.projectedPathPoint,
    required this.handImageBounds,
    required this.normalizedPenTipAnchor,
    required this.scaledFlippedPenTipAnchor,
    required this.finalDisplayedPenTip,
  });

  final Offset activeWorldPathPoint;
  final Offset projectedPathPoint;
  final Rect handImageBounds;
  final Offset normalizedPenTipAnchor;
  final Offset scaledFlippedPenTipAnchor;
  final Offset finalDisplayedPenTip;
  double get distanceInOutputPixels =>
      (finalDisplayedPenTip - projectedPathPoint).distance;
}
