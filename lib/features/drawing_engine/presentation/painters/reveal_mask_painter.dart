import 'dart:ui';
import 'dart:math' as math;

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';

void drawRevealMask({
  required Canvas canvas,
  required RevealedPath revealed,
  required Rect clip,
  required double brushWidth,
  required double featherWidth,
}) {
  if (revealed.revealStyle == RevealMaskStyle.directionalWipe) {
    _drawDirectionalWipe(
      canvas: canvas,
      revealed: revealed,
      clip: clip,
      featherWidth: featherWidth,
    );
    return;
  }
  final activeDirection = revealed.activeBrushDirection;
  if (activeDirection != null && activeDirection.distanceSquared > 0.000001) {
    canvas.save();
    _clipActiveBrushBehindNib(
      canvas: canvas,
      revealed: revealed,
      clip: clip,
      brushWidth: brushWidth,
      direction: activeDirection,
    );
    _drawBrush(canvas, revealed.path, brushWidth);
    canvas.restore();
    return;
  }
  _drawBrush(canvas, revealed.path, brushWidth);
}

void _drawBrush(Canvas canvas, Path path, double brushWidth) {
  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = brushWidth,
  );
}

void _clipActiveBrushBehindNib({
  required Canvas canvas,
  required RevealedPath revealed,
  required Rect clip,
  required double brushWidth,
  required Offset direction,
}) {
  final magnitude = direction.distance;
  final forward = direction / magnitude;
  final sideways = Offset(-forward.dy, forward.dx);
  var frontier = -double.maxFinite;
  for (final metric in revealed.path.computeMetrics()) {
    final sampleCount = math.max(8, math.min(64, (metric.length / 12).ceil()));
    for (var index = 0; index <= sampleCount; index++) {
      final tangent = metric.getTangentForOffset(
        metric.length * index / sampleCount,
      );
      if (tangent == null) continue;
      frontier = math.max(frontier, _dot(tangent.position, forward));
    }
  }
  if (!frontier.isFinite) return;
  final boundary = forward * frontier;
  final extent = math.max(clip.width, clip.height) + brushWidth * 2 + 8;
  final gate = Path()
    ..addPolygon([
      boundary + sideways * extent,
      boundary - sideways * extent,
      boundary - sideways * extent - forward * extent * 2,
      boundary + sideways * extent - forward * extent * 2,
    ], true);
  canvas.clipPath(gate, doAntiAlias: true);
}

double _dot(Offset first, Offset second) =>
    first.dx * second.dx + first.dy * second.dy;

void _drawDirectionalWipe({
  required Canvas canvas,
  required RevealedPath revealed,
  required Rect clip,
  required double featherWidth,
}) {
  final metrics = revealed.path.computeMetrics().toList(growable: false);
  if (metrics.isEmpty) return;
  final metric = metrics.first;
  final endpoint = metric.getTangentForOffset(metric.length)?.position;
  if (endpoint == null) return;
  final edge = endpoint.dx.clamp(clip.left, clip.right);
  final solidPaint = Paint()..color = const Color(0xFFFFFFFF);

  if (revealed.rightToLeft) {
    if (edge < clip.right) {
      canvas.drawRect(
        Rect.fromLTRB(edge, clip.top, clip.right, clip.bottom),
        solidPaint,
      );
    }
    return;
  }

  if (edge > clip.left) {
    canvas.drawRect(
      Rect.fromLTRB(clip.left, clip.top, edge, clip.bottom),
      solidPaint,
    );
  }
}
