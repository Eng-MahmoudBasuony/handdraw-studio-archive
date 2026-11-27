import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

/// Deterministically reduces raster centerlines and fits C1-continuous cubics.
class PolylineBezierFitter {
  const PolylineBezierFitter();

  StrokePathGeometry fit(List<Offset> source, {double tolerance = 0.0012}) {
    if (source.length < 2) {
      throw ArgumentError.value(
        source.length,
        'source',
        'Two points required.',
      );
    }
    final points = _simplify(source, tolerance);
    if (points.length == 2) {
      return StrokePathGeometry(
        start: points.first,
        segments: [StrokeLineSegment(end: points.last)],
      );
    }
    final segments = <StrokePathSegment>[];
    for (var index = 0; index < points.length - 1; index++) {
      final p0 = index == 0 ? points[index] : points[index - 1];
      final p1 = points[index];
      final p2 = points[index + 1];
      final p3 = index + 2 < points.length ? points[index + 2] : p2;
      segments.add(
        StrokeCubicSegment(
          control1: p1 + (p2 - p0) / 6,
          control2: p2 - (p3 - p1) / 6,
          end: p2,
        ),
      );
    }
    return StrokePathGeometry(start: points.first, segments: segments);
  }

  List<Offset> _simplify(List<Offset> points, double tolerance) {
    if (points.length <= 2) return List.unmodifiable(points);
    final keep = List<bool>.filled(points.length, false)
      ..first = true
      ..last = true;

    void visit(int start, int end) {
      var maximumDistance = 0.0;
      var maximumIndex = -1;
      for (var index = start + 1; index < end; index++) {
        final distance = _distanceToSegment(
          points[index],
          points[start],
          points[end],
        );
        if (distance > maximumDistance) {
          maximumDistance = distance;
          maximumIndex = index;
        }
      }
      if (maximumIndex < 0 || maximumDistance <= tolerance) return;
      keep[maximumIndex] = true;
      visit(start, maximumIndex);
      visit(maximumIndex, end);
    }

    visit(0, points.length - 1);
    return List.unmodifiable([
      for (var index = 0; index < points.length; index++)
        if (keep[index]) points[index],
    ]);
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.distanceSquared;
    if (lengthSquared <= 0.0000000001) return (point - start).distance;
    final progress =
        ((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
        lengthSquared;
    final closest = start + delta * progress.clamp(0.0, 1.0);
    return (point - closest).distance;
  }
}
