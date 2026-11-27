import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('timeline time and duration reject negative values', () {
    expect(() => TimelineTime.fromMicroseconds(-1), throwsRangeError);
    expect(() => TimelineDuration.fromMicroseconds(-1), throwsRangeError);
  });

  test('timeline arithmetic stays integer based and ordered', () {
    final start = TimelineTime.fromMicroseconds(1250000);
    final delay = TimelineDuration.fromMicroseconds(250000);
    final end = start + delay;

    expect(end.microseconds, 1500000);
    expect(end.difference(start), delay);
    expect(start.compareTo(end), isNegative);
    expect(
      end.clampTo(TimelineDuration.fromMicroseconds(1400000)),
      TimelineTime.fromMicroseconds(1400000),
    );
  });

  test('duration subtraction cannot produce a negative result', () {
    final shorter = TimelineDuration.fromMicroseconds(100);
    final longer = TimelineDuration.fromMicroseconds(200);

    expect(() => shorter - longer, throwsRangeError);
  });

  test('Duration conversion is lossless at microsecond precision', () {
    const source = Duration(microseconds: 987654321);

    expect(TimelineTime.fromDuration(source).asDuration, source);
    expect(TimelineDuration.fromDuration(source).asDuration, source);
  });
}
