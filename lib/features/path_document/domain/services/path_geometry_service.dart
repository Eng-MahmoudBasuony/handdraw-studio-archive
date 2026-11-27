import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

class PathGeometryService {
  const PathGeometryService();

  Path render(StrokePathGeometry geometry, Rect destination) =>
      geometry.toPath(destination);

  StrokePathGeometry reverse(StrokePathGeometry geometry) =>
      geometry.reversed();

  Rect bounds(StrokePathGeometry geometry) =>
      geometry.toPath(const Rect.fromLTWH(0, 0, 1, 1)).getBounds();

  double length(StrokePathGeometry geometry, Rect destination) => geometry
      .toPath(destination)
      .computeMetrics()
      .fold(0, (total, metric) => total + metric.length);
}
