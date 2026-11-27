import 'dart:math' as math;
import 'package:handdraw_studio/features/camera/domain/models/compiled_camera_track.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraResolver {
  const CameraResolver();
  ResolvedCameraState resolveAt(CompiledCameraTrack track, TimelineTime time) {
    if (!track.enabled ||
        track.shots.isEmpty ||
        time.compareTo(track.shots.first.interval.start) < 0) {
      return ResolvedSingleCameraView(track.defaultView);
    }
    final shotIndex = _lastShotStartingAtOrBefore(track.shots, time);
    final shot = track.shots[shotIndex];
    if (!shot.interval.contains(time)) {
      return ResolvedSingleCameraView(shot.finalView);
    }
    if (time == shot.interval.start) {
      return ResolvedSingleCameraView(shot.startView);
    }
    final segment = _segmentAt(shot.segments, time);
    if (segment == null || segment.kind == CompiledCameraSegmentKind.hold) {
      return ResolvedSingleCameraView(segment?.toView ?? shot.finalView);
    }
    final elapsed = time.difference(segment.interval.start).microseconds;
    final t = (elapsed / segment.interval.duration.microseconds).clamp(
      0.0,
      1.0,
    );
    final eased = _ease(segment.easing, t);
    if (segment.kind == CompiledCameraSegmentKind.fade) {
      return ResolvedCameraBlend(
        fromView: segment.fromView,
        toView: segment.toView,
        targetOpacity: eased,
      );
    }
    return ResolvedSingleCameraView(
      CameraView(
        centerX: _lerp(segment.fromView.centerX, segment.toView.centerX, eased),
        centerY: _lerp(segment.fromView.centerY, segment.toView.centerY, eased),
        viewportWidth: math.exp(
          _lerp(
            math.log(segment.fromView.viewportWidth),
            math.log(segment.toView.viewportWidth),
            eased,
          ),
        ),
      ),
    );
  }

  int _lastShotStartingAtOrBefore(
    List<CompiledCameraShot> shots,
    TimelineTime time,
  ) {
    var low = 0, high = shots.length - 1, result = 0;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (shots[middle].interval.start.compareTo(time) <= 0) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  CompiledCameraSegment? _segmentAt(
    List<CompiledCameraSegment> segments,
    TimelineTime time,
  ) {
    var low = 0, high = segments.length - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final item = segments[middle];
      if (time.compareTo(item.interval.start) < 0) {
        high = middle - 1;
      } else if (time.compareTo(item.interval.end) >= 0) {
        low = middle + 1;
      } else {
        return item;
      }
    }
    return null;
  }

  double _ease(CameraEasing easing, double t) => switch (easing) {
    CameraEasing.linear => t,
    CameraEasing.easeIn => t * t,
    CameraEasing.easeOut => 1 - (1 - t) * (1 - t),
    CameraEasing.easeInOut =>
      t < .5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2).toDouble() / 2,
  };
  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
