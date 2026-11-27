import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_duration_report.dart';

void main() {
  test(
    'reports drawing, voice, audio, camera, hold, and global ends separately',
    () {
      final timeline = CompiledTimeline(
        dependencyKey: TimelineDependencyKey(
          projectId: ProjectId('duration'),
          documentRevision: 1,
        ),
        duration: TimelineDuration.fromMicroseconds(19000000),
        contentEnd: TimelineTime.fromMicroseconds(19000000),
        drawing: CompiledDrawingTimelineTrack(
          interval: TimelineInterval(
            start: TimelineTime.zero,
            end: TimelineTime.fromMicroseconds(6000000),
          ),
          sections: const [],
        ),
        audio: const [],
        voiceGuide: CompiledVoiceGuideTimelineTrack(
          audioTrackId: AudioTrackId('voice'),
          assetId: ProjectAssetId('asset'),
          interval: TimelineInterval(
            start: TimelineTime.zero,
            end: TimelineTime.fromMicroseconds(19000000),
          ),
          sourceOffset: TimelineTime.zero,
          affectsTimelineDuration: true,
          referenceOnly: true,
          muted: false,
        ),
        sceneMarkers: const [],
      );
      final report = TimelineDurationReport.fromCompiled(timeline);
      expect(report.drawingEnd.microseconds, 6000000);
      expect(report.voiceGuideEnd.microseconds, 19000000);
      expect(report.cameraEnd, TimelineTime.zero);
      expect(report.explicitHoldEnd, TimelineTime.zero);
      expect(report.resolvedGlobalDuration.microseconds, 19000000);
    },
  );
}
