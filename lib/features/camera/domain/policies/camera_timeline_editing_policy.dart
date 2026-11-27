import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraTimelineEditingPolicy {
  const CameraTimelineEditingPolicy();
  static final defaultShotDuration = TimelineDuration.fromDuration(
    const Duration(seconds: 2),
  );
  static final minimumShotDuration = TimelineDuration.fromDuration(
    const Duration(milliseconds: 100),
  );
  TimelineTime nearestAvailableStart({
    required TimelineTime requested,
    required TimelineDuration duration,
    required List<CameraShot> shots,
  }) {
    var candidate = requested;
    for (final shot in shots) {
      final end = candidate.microseconds + duration.microseconds;
      if (end <= shot.startTime.microseconds) return candidate;
      if (candidate.microseconds < shot.endTime.microseconds) {
        candidate = shot.endTime;
      }
    }
    return candidate;
  }
}
