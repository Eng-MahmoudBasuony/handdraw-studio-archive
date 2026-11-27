import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/operations/camera_document_operations.dart';
import 'package:handdraw_studio/features/camera/domain/services/scene_camera_track_projector.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_factory.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

void main() {
  const projector = SceneCameraTrackProjector();

  test('scene-owned clip follows scene timing and scales its phases', () {
    final sceneId = SceneId('scene-a');
    final sectionId = SectionId('section-a');
    final shot = CameraShot(
      id: CameraShotId('shot-a'),
      startTime: TimelineTime.zero,
      duration: TimelineDuration.fromMicroseconds(4000000),
      authorship: CameraAuthorship.manual,
      isLocked: false,
      ownerSceneId: sceneId,
      keyframes: [
        CameraKeyframe(
          id: CameraKeyframeId('key-a'),
          offset: TimelineTime.zero,
          view: const CameraView.identity(),
        ),
        CameraKeyframe(
          id: CameraKeyframeId('key-b'),
          offset: TimelineTime.fromMicroseconds(1000000),
          view: const CameraView(centerX: .5, centerY: .5, viewportWidth: .5),
          incomingTransition: CameraTransition(
            type: CameraTransitionType.move,
            duration: TimelineDuration.fromMicroseconds(1000000),
            easing: CameraEasing.easeInOut,
          ),
        ),
        CameraKeyframe(
          id: CameraKeyframeId('key-c'),
          offset: TimelineTime.fromMicroseconds(4000000),
          view: const CameraView.identity(),
          incomingTransition: CameraTransition(
            type: CameraTransitionType.move,
            duration: TimelineDuration.fromMicroseconds(1000000),
            easing: CameraEasing.easeInOut,
          ),
        ),
      ],
    );
    final intervals = projector.resolveSceneIntervals(
      scenes: [
        ProjectScene(id: sceneId, name: 'Scene A', sectionIds: [sectionId]),
      ],
      sectionIntervals: {
        sectionId: TimelineInterval(
          start: TimelineTime.fromMicroseconds(2000000),
          end: TimelineTime.fromMicroseconds(10000000),
          intervalType: 'test',
          entityId: sectionId.value,
          sourceOperation: 'test',
          documentRevision: 1,
        ),
      },
      documentRevision: 1,
    );
    final projected = projector.project(
      track: ProjectCameraTrack(id: CameraTrackId('track'), shots: [shot]),
      sceneIntervals: intervals,
    );

    expect(projected.shots.single.startTime.microseconds, 2000000);
    expect(projected.shots.single.duration.microseconds, 8000000);
    expect(projected.shots.single.keyframes[1].offset.microseconds, 2000000);
    expect(
      projected
          .shots
          .single
          .keyframes[1]
          .incomingTransition
          .duration
          .microseconds,
      2000000,
    );
    expect(projected.shots.single.keyframes.last.offset.microseconds, 8000000);
  });

  test('installing a scene clip is atomic and rejects duplicate ownership', () {
    final sceneId = SceneId('scene-a');
    final sectionId = SectionId('section-a');
    final base = const ProjectDocumentFactory()
        .createEmpty(ids: FakeIdGenerator())
        .copyWith(
          scenes: [
            ProjectScene(id: sceneId, name: 'Scene A', sectionIds: [sectionId]),
          ],
          sections: [
            ProjectSection(
              id: sectionId,
              name: 'Section A',
              strokeIds: const [],
            ),
          ],
          sectionOrder: [sectionId],
        );
    final clip = CameraShot(
      id: CameraShotId('scene-shot'),
      startTime: TimelineTime.zero,
      duration: TimelineDuration.fromMicroseconds(3000000),
      authorship: CameraAuthorship.manual,
      isLocked: false,
      ownerSceneId: sceneId,
      keyframes: [
        CameraKeyframe(
          id: CameraKeyframeId('scene-key'),
          offset: TimelineTime.zero,
          view: const CameraView.identity(),
        ),
      ],
    );

    final result = const CameraDocumentOperations().installSceneClip(
      base,
      trackId: CameraTrackId('track'),
      clip: clip,
    );

    expect(result.isSuccess, isTrue);
    expect(result.affectedScopes, {DocumentScope.camera});
    expect(result.document.cameraTrack!.shots.single.ownerSceneId, sceneId);
    expect(result.document.timeline.camera.enabled, isTrue);
  });
}
