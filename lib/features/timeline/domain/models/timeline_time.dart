/// A non-negative absolute position on the project timeline.
///
/// Microseconds are the canonical persisted and runtime unit. Presentation
/// layers may format this value as decimal seconds, but timeline arithmetic
/// must stay integer based.
final class TimelineTime implements Comparable<TimelineTime> {
  const TimelineTime._(this.microseconds);

  factory TimelineTime.fromMicroseconds(int microseconds) {
    if (microseconds < 0) {
      throw RangeError.value(
        microseconds,
        'microseconds',
        'Timeline time cannot be negative.',
      );
    }
    return TimelineTime._(microseconds);
  }

  factory TimelineTime.fromDuration(Duration duration) =>
      TimelineTime.fromMicroseconds(duration.inMicroseconds);

  static const zero = TimelineTime._(0);

  final int microseconds;

  Duration get asDuration => Duration(microseconds: microseconds);

  TimelineTime operator +(TimelineDuration duration) =>
      TimelineTime._(microseconds + duration.microseconds);

  TimelineDuration difference(TimelineTime earlier) {
    if (earlier.microseconds > microseconds) {
      throw RangeError.value(
        earlier.microseconds,
        'earlier',
        'The earlier time cannot be after this time.',
      );
    }
    return TimelineDuration._(microseconds - earlier.microseconds);
  }

  TimelineTime clampTo(TimelineDuration duration) =>
      microseconds <= duration.microseconds
      ? this
      : TimelineTime._(duration.microseconds);

  @override
  int compareTo(TimelineTime other) =>
      microseconds.compareTo(other.microseconds);

  @override
  bool operator ==(Object other) =>
      other is TimelineTime && other.microseconds == microseconds;

  @override
  int get hashCode => microseconds.hashCode;

  @override
  String toString() => 'TimelineTime(${microseconds}us)';
}

/// A non-negative amount of time in the project timeline.
final class TimelineDuration implements Comparable<TimelineDuration> {
  const TimelineDuration._(this.microseconds);

  factory TimelineDuration.fromMicroseconds(int microseconds) {
    if (microseconds < 0) {
      throw RangeError.value(
        microseconds,
        'microseconds',
        'Timeline duration cannot be negative.',
      );
    }
    return TimelineDuration._(microseconds);
  }

  factory TimelineDuration.fromDuration(Duration duration) =>
      TimelineDuration.fromMicroseconds(duration.inMicroseconds);

  static const zero = TimelineDuration._(0);

  final int microseconds;

  bool get isZero => microseconds == 0;

  Duration get asDuration => Duration(microseconds: microseconds);

  TimelineDuration operator +(TimelineDuration other) =>
      TimelineDuration._(microseconds + other.microseconds);

  TimelineDuration operator -(TimelineDuration other) {
    if (other.microseconds > microseconds) {
      throw RangeError.value(
        other.microseconds,
        'other',
        'Timeline duration subtraction cannot produce a negative value.',
      );
    }
    return TimelineDuration._(microseconds - other.microseconds);
  }

  @override
  int compareTo(TimelineDuration other) =>
      microseconds.compareTo(other.microseconds);

  @override
  bool operator ==(Object other) =>
      other is TimelineDuration && other.microseconds == microseconds;

  @override
  int get hashCode => microseconds.hashCode;

  @override
  String toString() => 'TimelineDuration(${microseconds}us)';
}
