import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

class PathSamplingService {
  const PathSamplingService();

  List<Offset> sample(StrokePathGeometry geometry, {int curveSteps = 12}) =>
      geometry.sample(cubicSteps: curveSteps);
}
