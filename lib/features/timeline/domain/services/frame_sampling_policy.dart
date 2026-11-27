import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class FrameSamplingPolicy {
  const FrameSamplingPolicy();

  int frameCount({
    required TimelineDuration duration,
    required FrameRate frameRate,
  }) {
    if (duration.isZero) return 0;
    final numerator = duration.microseconds * frameRate.numerator;
    final denominator = Duration.microsecondsPerSecond * frameRate.denominator;
    return (numerator + denominator - 1) ~/ denominator;
  }

  TimelineTime timeForFrame({
    required int index,
    required TimelineDuration duration,
    required FrameRate frameRate,
  }) {
    final count = frameCount(duration: duration, frameRate: frameRate);
    if (index < 0 || index >= count) {
      throw RangeError.range(index, 0, count - 1, 'index');
    }
    return TimelineTime.fromMicroseconds(
      index *
          Duration.microsecondsPerSecond *
          frameRate.denominator ~/
          frameRate.numerator,
    );
  }

  /// Returns the export-frame sample that owns [time]. Preview uses this to
  /// avoid resolving and repainting the same video frame more than once when
  /// the display refresh rate is higher than the project frame rate.
  int? frameIndexForTime({
    required TimelineTime time,
    required TimelineDuration duration,
    required FrameRate frameRate,
  }) {
    final count = frameCount(duration: duration, frameRate: frameRate);
    if (count == 0) return null;
    final clampedMicroseconds = time.microseconds.clamp(
      0,
      duration.microseconds,
    );
    final index =
        clampedMicroseconds *
        frameRate.numerator ~/
        (Duration.microsecondsPerSecond * frameRate.denominator);
    return index.clamp(0, count - 1);
  }
}
