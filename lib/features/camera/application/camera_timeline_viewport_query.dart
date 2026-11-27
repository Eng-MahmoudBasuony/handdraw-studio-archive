import 'dart:math' as math;

import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

final class CameraTimelineViewportQuery {
  const CameraTimelineViewportQuery();

  Iterable<CameraShot> visibleShots({
    required List<CameraShot> shots,
    required double viewportStart,
    required double viewportWidth,
    required double pixelsPerSecond,
  }) sync* {
    if (shots.isEmpty || pixelsPerSecond <= 0 || viewportWidth <= 0) return;
    final startUs =
        (viewportStart / pixelsPerSecond * Duration.microsecondsPerSecond)
            .floor();
    final endUs =
        ((viewportStart + viewportWidth) /
                pixelsPerSecond *
                Duration.microsecondsPerSecond)
            .ceil();
    var low = 0;
    var high = shots.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (shots[middle].startTime.microseconds < startUs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var index = math.max(0, low - 1);
    while (index < shots.length) {
      final shot = shots[index++];
      if (shot.startTime.microseconds > endUs) break;
      if (shot.endTime.microseconds >= startUs) yield shot;
    }
  }
}
