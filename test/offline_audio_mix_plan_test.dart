import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/export/domain/offline_audio_mix_plan.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test(
    'offline plan includes only export audio and structurally excludes voice',
    () {
      final timeline = CompiledTimeline(
        dependencyKey: TimelineDependencyKey(
          projectId: ProjectId('p'),
          documentRevision: 1,
        ),
        duration: TimelineDuration.fromMicroseconds(1000),
        contentEnd: TimelineTime.fromMicroseconds(1000),
        drawing: null,
        audio: [
          _audio('included', referenceOnly: false),
          _audio('reference', referenceOnly: true),
          _audio('muted', referenceOnly: false, muted: true),
        ],
        voiceGuide: CompiledVoiceGuideTimelineTrack(
          audioTrackId: AudioTrackId('voice'),
          assetId: ProjectAssetId('asset-voice'),
          interval: TimelineInterval(
            start: TimelineTime.zero,
            end: TimelineTime.fromMicroseconds(1000),
          ),
          sourceOffset: TimelineTime.zero,
          affectsTimelineDuration: true,
          referenceOnly: true,
          muted: false,
        ),
        sceneMarkers: const [],
      );
      final plan = OfflineAudioMixPlan.fromTimeline(timeline);
      expect(plan.clips.map((clip) => clip.trackId), [
        AudioTrackId('included'),
      ]);
      expect(
        plan.clips.any((clip) => clip.trackId == AudioTrackId('voice')),
        isFalse,
      );
    },
  );
}

CompiledAudioTimelineTrack _audio(
  String id, {
  required bool referenceOnly,
  bool muted = false,
}) => CompiledAudioTimelineTrack(
  audioTrackId: AudioTrackId(id),
  assetId: ProjectAssetId('asset-$id'),
  interval: TimelineInterval(
    start: TimelineTime.zero,
    end: TimelineTime.fromMicroseconds(1000),
  ),
  sourceOffset: TimelineTime.zero,
  affectsTimelineDuration: true,
  referenceOnly: referenceOnly,
  muted: muted,
);
