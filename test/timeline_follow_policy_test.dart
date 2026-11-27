import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/presentation/timeline_follow_policy.dart';

void main() {
  const policy = TimelineFollowPolicy();

  for (final duration in [6.0, 20.0, 60.0]) {
    test('follow keeps context for a ${duration.toInt()} second timeline', () {
      const viewport = 1000.0;
      final content = duration * 150;
      final maximum = (content - viewport).clamp(0, double.infinity).toDouble();
      final target = policy.targetOffset(
        enabled: true,
        playheadX: duration * .8 * 150,
        currentOffset: 0,
        viewportWidth: viewport,
        maximumOffset: maximum,
      );
      if (maximum == 0) {
        expect(target, isNull);
      } else {
        expect(target, inInclusiveRange(0, maximum));
      }
    });
  }

  test('follow off and playhead inside threshold never move scroll', () {
    expect(
      policy.targetOffset(
        enabled: false,
        playheadX: 900,
        currentOffset: 0,
        viewportWidth: 1000,
        maximumOffset: 2000,
      ),
      isNull,
    );
    expect(
      policy.targetOffset(
        enabled: true,
        playheadX: 500,
        currentOffset: 0,
        viewportWidth: 1000,
        maximumOffset: 2000,
      ),
      isNull,
    );
  });
}
