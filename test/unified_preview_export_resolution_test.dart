import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';
import 'package:handdraw_studio/features/timeline/domain/services/unified_project_frame_resolver.dart';

void main() {
  const resolver = UnifiedProjectFrameResolver();
  const sampling = FrameSamplingPolicy();

  for (final rate in [
    FrameRate.fps24,
    FrameRate.fps25,
    FrameRate.fps30,
    FrameRate.fps50,
    FrameRate.fps60,
    FrameRate.ntsc2997,
  ]) {
    test('preview and export resolve identical semantic frames at $rate', () {
      final timeline = _timeline();
      final count = sampling.frameCount(
        duration: timeline.duration,
        frameRate: rate,
      );
      for (final index in {0, count ~/ 3, count ~/ 2, count - 1}) {
        final time = index == count - 1
            ? TimelineTime.fromMicroseconds(timeline.duration.microseconds)
            : sampling.timeForFrame(
                index: index,
                duration: timeline.duration,
                frameRate: rate,
              );
        final preview = resolver.resolveForPreview(timeline, time);
        final export = resolver.resolveForExportFrame(
          timeline: timeline,
          frameIndex: index,
          frameRate: rate,
        );
        expect(_signature(preview), _signature(export));
      }
    });
  }

  test('the final MOV frame resolves the exact terminal visibility state', () {
    final timeline = _timeline();
    final count = sampling.frameCount(
      duration: timeline.duration,
      frameRate: FrameRate.fps30,
    );

    final frame = resolver.resolveForExportFrame(
      timeline: timeline,
      frameIndex: count - 1,
      frameRate: FrameRate.fps30,
    );

    expect(frame.time, TimelineTime.fromMicroseconds(2000000));
    expect(frame.isFinalFrame, isTrue);
  });

  test(
    'playback rate never changes resolved state for the same absolute time',
    () {
      final timeline = _timeline();
      final time = TimelineTime.fromMicroseconds(750000);
      final normal = resolver.resolveForPreview(timeline, time);
      final fast = resolver.resolveForPreview(timeline, time);
      expect(_signature(normal), _signature(fast));
    },
  );
}

CompiledTimeline _timeline() {
  final section = SectionId('section');
  return CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: ProjectId('project'),
      documentRevision: 1,
    ),
    duration: TimelineDuration.fromMicroseconds(2000000),
    contentEnd: TimelineTime.fromMicroseconds(1500000),
    drawing: CompiledDrawingTimelineTrack(
      interval: TimelineInterval(
        start: TimelineTime.fromMicroseconds(250000),
        end: TimelineTime.fromMicroseconds(1250000),
      ),
      sections: [
        CompiledDrawingSection(
          sectionId: section,
          interval: TimelineInterval(
            start: TimelineTime.fromMicroseconds(500000),
            end: TimelineTime.fromMicroseconds(1000000),
          ),
        ),
      ],
    ),
    audio: const [],
    voiceGuide: null,
    sceneMarkers: const [],
  );
}

String _signature(ResolvedProjectFrame frame) =>
    '${frame.time.microseconds}:${frame.drawing?.localTime.microseconds}:'
    '${frame.drawing?.duration.microseconds}:${frame.drawing?.sectionId}:'
    '${frame.drawing?.isHeld}:${frame.isFinalFrame}';
