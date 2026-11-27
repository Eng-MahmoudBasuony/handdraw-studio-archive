import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

/// Product-level safety limits kept outside the timeline arithmetic engine.
abstract final class ProjectLimits {
  static const maximumDurationMicroseconds = 24 * 60 * 60 * 1000000;

  /// The largest frame rate currently offered by the product UI.
  static const maximumFramesPerSecond = 60;

  static final maximumDuration = TimelineDuration.fromMicroseconds(
    maximumDurationMicroseconds,
  );

  static bool supportsDuration(TimelineDuration duration) =>
      duration.compareTo(maximumDuration) <= 0;

  static void validateDuration(TimelineDuration duration) {
    if (!supportsDuration(duration)) {
      throw RangeError.value(
        duration.microseconds,
        'duration',
        'Project duration cannot exceed 24 hours.',
      );
    }
  }
}
