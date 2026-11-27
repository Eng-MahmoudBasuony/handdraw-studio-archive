import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/policies/project_limits.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('project duration limit is centralized at 24 hours', () {
    expect(
      ProjectLimits.maximumDurationMicroseconds,
      const Duration(hours: 24).inMicroseconds,
    );
    expect(ProjectLimits.maximumFramesPerSecond, 60);
    expect(
      ProjectLimits.supportsDuration(ProjectLimits.maximumDuration),
      isTrue,
    );
  });

  test('duration beyond the product limit reports a clear range error', () {
    final tooLong = TimelineDuration.fromMicroseconds(
      ProjectLimits.maximumDurationMicroseconds + 1,
    );

    expect(ProjectLimits.supportsDuration(tooLong), isFalse);
    expect(
      () => ProjectLimits.validateDuration(tooLong),
      throwsA(
        isA<RangeError>().having(
          (error) => error.message,
          'message',
          contains('24 hours'),
        ),
      ),
    );
  });
}
