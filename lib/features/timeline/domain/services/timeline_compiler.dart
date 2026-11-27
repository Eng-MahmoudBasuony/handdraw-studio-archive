import 'dart:math' as math;

import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/ports/drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_timeline_compiler.dart';
import 'package:handdraw_studio/features/camera/domain/services/scene_camera_track_projector.dart';

final class TimelineCompiler {
  const TimelineCompiler({required this.drawingAdapter});

  final DrawingTimelineCompilerAdapter drawingAdapter;

  CompiledTimeline compile({
    required ProjectDocument document,
    required int documentRevision,
  }) {
    final timeline = document.timeline;
    final dependencyKey = TimelineDependencyKey(
      projectId: document.id,
      documentRevision: documentRevision,
    );
    final leadingUs = timeline.leadingHold.microseconds;
    CompiledDrawingTimelineTrack? drawing;
    var contentEndUs = leadingUs;
    if (timeline.drawing.enabled) {
      final adapted = drawingAdapter.compile(document);
      final interval = TimelineInterval(
        start: TimelineTime.fromMicroseconds(leadingUs),
        end: TimelineTime.fromMicroseconds(
          leadingUs + adapted.duration.microseconds,
        ),
        intervalType: 'drawing-track',
        entityId: document.id.value,
        sourceOperation: 'timeline-compile',
        documentRevision: documentRevision,
      );
      drawing = CompiledDrawingTimelineTrack(
        interval: interval,
        sections: [
          for (final section in adapted.sections)
            CompiledDrawingSection(
              sectionId: section.sectionId,
              interval: TimelineInterval(
                start: TimelineTime.fromMicroseconds(
                  leadingUs + section.interval.start.microseconds,
                ),
                end: TimelineTime.fromMicroseconds(
                  leadingUs + section.interval.end.microseconds,
                ),
                intervalType: 'drawing-section',
                entityId: section.sectionId.value,
                sourceOperation: 'timeline-compile',
                documentRevision: documentRevision,
              ),
            ),
        ],
      );
      contentEndUs = math.max(contentEndUs, interval.end.microseconds);
    }

    final audioById = {
      for (final track in document.audioTracks) track.id: track,
    };
    final voiceId = timeline.voiceGuide?.audioTrackId;
    final audio = <CompiledAudioTimelineTrack>[];
    for (final reference in timeline.audio) {
      final track = audioById[reference.audioTrackId];
      if (track == null) continue;
      final startUs = leadingUs + track.start.microseconds;
      final endUs = startUs + track.duration.microseconds;
      if (track.id != voiceId) {
        audio.add(
          CompiledAudioTimelineTrack(
            audioTrackId: track.id,
            assetId: track.assetId,
            interval: TimelineInterval(
              start: TimelineTime.fromMicroseconds(startUs),
              end: TimelineTime.fromMicroseconds(endUs),
              intervalType: 'audio-track',
              entityId: track.id.value,
              sourceOperation: 'timeline-compile',
              documentRevision: documentRevision,
            ),
            sourceOffset: track.sourceOffset,
            affectsTimelineDuration: track.affectsTimelineDuration,
            referenceOnly:
                track.exportPolicy == AudioExportPolicy.referenceOnly,
            muted: track.muted,
          ),
        );
      }
      if (track.affectsTimelineDuration) {
        contentEndUs = math.max(contentEndUs, endUs);
      }
    }

    CompiledVoiceGuideTimelineTrack? voiceGuide;
    final voiceTrack = voiceId == null ? null : audioById[voiceId];
    if (voiceTrack != null) {
      final startUs = leadingUs + voiceTrack.start.microseconds;
      final endUs = startUs + voiceTrack.duration.microseconds;
      voiceGuide = CompiledVoiceGuideTimelineTrack(
        audioTrackId: voiceTrack.id,
        assetId: voiceTrack.assetId,
        interval: TimelineInterval(
          start: TimelineTime.fromMicroseconds(startUs),
          end: TimelineTime.fromMicroseconds(endUs),
          intervalType: 'voice-guide',
          entityId: voiceTrack.id.value,
          sourceOperation: 'timeline-compile',
          documentRevision: documentRevision,
        ),
        sourceOffset: voiceTrack.sourceOffset,
        affectsTimelineDuration: voiceTrack.affectsTimelineDuration,
        referenceOnly:
            voiceTrack.exportPolicy == AudioExportPolicy.referenceOnly,
        muted: voiceTrack.muted,
      );
      if (voiceTrack.affectsTimelineDuration) {
        contentEndUs = math.max(contentEndUs, endUs);
      }
    }

    final sourceCamera = document.cameraTrack;
    final sceneProjector = const SceneCameraTrackProjector();
    final sceneIntervals = sceneProjector.resolveSceneIntervals(
      scenes: document.scenes,
      sectionIntervals: {
        for (final section
            in drawing?.sections ?? const <CompiledDrawingSection>[])
          section.sectionId: TimelineInterval(
            start: TimelineTime.fromMicroseconds(
              section.interval.start.microseconds - leadingUs,
            ),
            end: TimelineTime.fromMicroseconds(
              section.interval.end.microseconds - leadingUs,
            ),
            intervalType: 'scene-camera-section',
            entityId: section.sectionId.value,
            sourceOperation: 'timeline-compile',
            documentRevision: documentRevision,
          ),
      },
      documentRevision: documentRevision,
    );
    final projectedCamera = sourceCamera == null
        ? null
        : sceneProjector.project(
            track: sourceCamera,
            sceneIntervals: sceneIntervals,
          );
    final camera = timeline.camera.enabled && sourceCamera != null
        ? const CameraTimelineCompiler().compile(
            track: projectedCamera!,
            dependencyKey: dependencyKey,
            offset: TimelineDuration.fromMicroseconds(leadingUs),
          )
        : null;
    if (camera != null && camera.enabled && camera.shots.isNotEmpty) {
      contentEndUs = math.max(contentEndUs, camera.contentEnd.microseconds);
    }
    final durationUs = contentEndUs + timeline.trailingHold.microseconds;
    return CompiledTimeline(
      dependencyKey: dependencyKey,
      duration: TimelineDuration.fromMicroseconds(durationUs),
      contentEnd: TimelineTime.fromMicroseconds(contentEndUs),
      drawing: drawing,
      camera: camera,
      audio: audio,
      voiceGuide: voiceGuide,
      sceneMarkers: [
        for (final marker in timeline.sceneMarkers)
          CompiledSceneMarker(
            sceneId: marker.sceneId,
            time: TimelineTime.fromMicroseconds(
              leadingUs + marker.time.microseconds,
            ),
          ),
      ],
    );
  }
}
