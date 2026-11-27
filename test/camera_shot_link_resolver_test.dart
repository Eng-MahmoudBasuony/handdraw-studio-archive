import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_shot_link_resolver.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  const resolver = CameraShotLinkResolver();
  final spans = [
    _span('a', 'Artwork 1', 0, 2),
    _span('b', 'Artwork 2', 2, 4),
    _span('c', 'Final artwork', 4, 6),
  ];

  test('uses the single timeline block covered by a free camera shot', () {
    final link = resolver.resolve(shot: _shot(2.2, 1), timelineSpans: spans);

    expect(link.sectionIds, ['b']);
    expect(link.displayName(isArabic: false), 'Artwork 2');
  });

  test('describes a camera shot that continues through the last scene', () {
    final link = resolver.resolve(shot: _shot(2, 4), timelineSpans: spans);

    expect(link.sectionIds, ['b', 'c']);
    expect(link.displayName(isArabic: true), 'Artwork 2 — إلى آخر مشهد');
    expect(link.displayName(isArabic: false), 'Artwork 2 — to last scene');
  });

  test('scene ownership wins over incidental temporal overlap', () {
    final link = resolver.resolve(
      shot: _shot(0, 6),
      timelineSpans: spans,
      ownedSectionIds: const ['b'],
    );

    expect(link.sectionIds, ['b']);
    expect(link.displayName(isArabic: false), 'Artwork 2');
  });

  test('partial first scene uses the explicit first and last names', () {
    final link = resolver.resolve(shot: _shot(2.5, 3.5), timelineSpans: spans);

    expect(link.reachesTimelineEnd, isFalse);
    expect(link.displayName(isArabic: false), 'Artwork 2 — Final artwork');
  });
}

CameraTimelineContentSpan _span(
  String id,
  String name,
  double start,
  double end,
) => CameraTimelineContentSpan(
  id: id,
  name: name,
  start: _time(start),
  end: _time(end),
);

CameraShot _shot(double start, double duration) => CameraShot(
  id: CameraShotId('shot'),
  startTime: _time(start),
  duration: TimelineDuration.fromMicroseconds(
    (duration * Duration.microsecondsPerSecond).round(),
  ),
  authorship: CameraAuthorship.manual,
  isLocked: false,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('frame'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);

TimelineTime _time(double seconds) => TimelineTime.fromMicroseconds(
  (seconds * Duration.microsecondsPerSecond).round(),
);
