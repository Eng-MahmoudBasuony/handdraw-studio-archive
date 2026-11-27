import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

/// Identifies filled SVG contours that visually behave like pen strokes.
///
/// A compact card or badge should use a directional fill reveal. Thin bars,
/// brackets, stars, and outlined marks need a medial path so the hand follows
/// the visible artwork instead of travelling across its bounding box.
class SvgFilledPathTracePolicy {
  const SvgFilledPathTracePolicy();

  bool shouldTrace(StrokePathGeometry geometry) {
    if (!geometry.closed || geometry.isEmpty) return false;
    final points = geometry.sample(cubicSteps: 24);
    if (points.length < 3) return false;
    final bounds = geometry
        .toPath(const ui.Rect.fromLTWH(0, 0, 1, 1))
        .getBounds();
    if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0) return false;

    var twiceArea = 0.0;
    var perimeter = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      twiceArea += current.dx * next.dy - next.dx * current.dy;
      perimeter += (next - current).distance;
    }
    final area = twiceArea.abs() * 0.5;
    if (area <= 0 || perimeter <= 0) return false;
    final occupancy = area / (bounds.width * bounds.height);
    final compactness = area / math.pow(perimeter, 2);

    return occupancy < 0.58 || compactness < 0.03;
  }
}

/// Rasterizes one normalized vector contour in isolation for medial tracing.
///
/// Rendering each candidate separately prevents overlapping SVG elements from
/// leaking into each other's paths. The returned pixels use the same normalized
/// coordinate space as Preview and MOV export.
class SvgFilledPathRasterizer {
  const SvgFilledPathRasterizer({this.dimension = 2048});

  final int dimension;

  Future<ui.Image> rasterize(StrokePathGeometry geometry) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final destination = ui.Rect.fromLTWH(
      0,
      0,
      dimension.toDouble(),
      dimension.toDouble(),
    );
    canvas.drawPath(
      geometry.toPath(destination),
      ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.fill
        ..color = const ui.Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(dimension, dimension);
    picture.dispose();
    return image;
  }
}
