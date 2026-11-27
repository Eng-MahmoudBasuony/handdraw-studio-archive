import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

/// Resolves scene ownership into concrete timeline geometry.
///
/// Scene-owned shots keep their authored camera views and phase proportions,
/// while their start and duration follow the scene's current section timing.
/// This keeps editor, Preview, and export aligned after timing edits without
/// rewriting the project document as a side effect of compilation.
final class SceneCameraTrackProjector {
  const SceneCameraTrackProjector();

  CameraShot placeholder({
    required ProjectScene scene,
    required TimelineInterval interval,
  }) => CameraShot(
    id: CameraShotId('scene-camera-placeholder:${scene.id.value}'),
    startTime: interval.start,
    duration: interval.duration,
    authorship: CameraAuthorship.manual,
    isLocked: true,
    label: scene.name,
    ownerSceneId: scene.id,
    keyframes: const [],
  );

  Map<SceneId, TimelineInterval> resolveSceneIntervals({
    required List<ProjectScene> scenes,
    required Map<SectionId, TimelineInterval> sectionIntervals,
    required int documentRevision,
  }) {
    final result = <SceneId, TimelineInterval>{};
    for (final scene in scenes) {
      final members = [
        for (final id in scene.sectionIds) ?sectionIntervals[id],
      ];
      if (members.isEmpty) continue;
      final start = members
          .map((item) => item.start.microseconds)
          .reduce((a, b) => a < b ? a : b);
      final end = members
          .map((item) => item.end.microseconds)
          .reduce((a, b) => a > b ? a : b);
      if (end <= start) continue;
      result[scene.id] = TimelineInterval(
        start: TimelineTime.fromMicroseconds(start),
        end: TimelineTime.fromMicroseconds(end),
        intervalType: 'scene-camera-owner',
        entityId: scene.id.value,
        sourceOperation: 'scene-camera-project',
        documentRevision: documentRevision,
      );
    }
    return result;
  }

  ProjectCameraTrack project({
    required ProjectCameraTrack track,
    required Map<SceneId, TimelineInterval> sceneIntervals,
  }) => track.copyWith(
    shots: [
      for (final shot in track.shots)
        if (shot.ownerSceneId case final sceneId?)
          _projectShot(shot, sceneIntervals[sceneId])
        else
          shot,
    ]..sort((a, b) => a.startTime.compareTo(b.startTime)),
  );

  CameraShot _projectShot(CameraShot shot, TimelineInterval? interval) {
    if (interval == null || interval.duration.isZero) return shot;
    final sourceUs = shot.duration.microseconds;
    final targetUs = interval.duration.microseconds;
    if (sourceUs <= 0) {
      return shot.copyWith(
        startTime: interval.start,
        duration: interval.duration,
      );
    }
    TimelineDuration scaledDuration(TimelineDuration value) =>
        TimelineDuration.fromMicroseconds(
          (value.microseconds * targetUs / sourceUs).round().clamp(0, targetUs),
        );
    return shot.copyWith(
      startTime: interval.start,
      duration: interval.duration,
      keyframes: [
        for (final frame in shot.keyframes)
          frame.copyWith(
            offset: TimelineTime.fromMicroseconds(
              (frame.offset.microseconds * targetUs / sourceUs).round().clamp(
                0,
                targetUs,
              ),
            ),
            incomingTransition: frame.incomingTransition.copyWith(
              duration: scaledDuration(frame.incomingTransition.duration),
            ),
          ),
      ],
    );
  }
}
