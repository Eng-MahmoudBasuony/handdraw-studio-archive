import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class TimelineSnapResult {
  const TimelineSnapResult({required this.time, this.guide});
  final TimelineTime time;
  final TimelineTime? guide;
}

/// Shared presentation adapter that converts the pixel threshold once, then
/// returns canonical integer timeline values.
final class TimelineSnapService {
  const TimelineSnapService();
  TimelineSnapResult snap({
    required TimelineTime candidate,
    required Iterable<TimelineTime> targets,
    required double pixelsPerSecond,
    double thresholdPixels = 8,
    bool enabled = true,
  }) {
    if (!enabled || pixelsPerSecond <= 0) {
      return TimelineSnapResult(time: candidate);
    }
    final thresholdUs =
        (thresholdPixels * Duration.microsecondsPerSecond / pixelsPerSecond)
            .round();
    TimelineTime? best;
    var distance = thresholdUs + 1;
    for (final target in targets) {
      final delta = (target.microseconds - candidate.microseconds).abs();
      if (delta < distance && delta <= thresholdUs) {
        best = target;
        distance = delta;
      }
    }
    return TimelineSnapResult(time: best ?? candidate, guide: best);
  }
}
