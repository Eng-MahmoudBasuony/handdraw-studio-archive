import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/application/services/timeline_snap_service.dart';

void main() {
  const service = TimelineSnapService();

  test(
    'pixel threshold scales with zoom and returns integer timeline time',
    () {
      final target = TimelineTime.fromMicroseconds(1000000);
      final candidate = TimelineTime.fromMicroseconds(960000);
      expect(
        service
            .snap(candidate: candidate, targets: [target], pixelsPerSecond: 100)
            .time,
        target,
      );
      expect(
        service
            .snap(candidate: candidate, targets: [target], pixelsPerSecond: 400)
            .time,
        candidate,
      );
    },
  );

  test('modifier can disable snapping', () {
    final candidate = TimelineTime.fromMicroseconds(999999);
    final result = service.snap(
      candidate: candidate,
      targets: [TimelineTime.fromMicroseconds(1000000)],
      pixelsPerSecond: 100,
      enabled: false,
    );
    expect(result.time, candidate);
    expect(result.guide, isNull);
  });
}
