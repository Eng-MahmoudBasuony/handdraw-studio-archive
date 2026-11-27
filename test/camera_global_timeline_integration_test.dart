import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_compiler.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  test('scene-owned camera compiles to the exact drawing scene interval', () {
    final base = projectDocumentParityFixture();
    final sceneId = base.scenes.single.id;
    final track = ProjectCameraTrack(
      id: CameraTrackId('scene-camera-track'),
      shots: [
        CameraShot(
          id: CameraShotId('scene-camera-shot'),
          startTime: TimelineTime.fromMicroseconds(1000000),
          duration: TimelineDuration.fromMicroseconds(10000000),
          authorship: CameraAuthorship.manual,
          isLocked: false,
          ownerSceneId: sceneId,
          keyframes: [
            CameraKeyframe(
              id: CameraKeyframeId('scene-camera-start'),
              offset: TimelineTime.zero,
              view: const CameraView.identity(),
            ),
            CameraKeyframe(
              id: CameraKeyframeId('scene-camera-focus'),
              offset: TimelineTime.fromMicroseconds(10000000),
              view: const CameraView(
                centerX: .5,
                centerY: .5,
                viewportWidth: .5,
              ),
              incomingTransition: CameraTransition(
                type: CameraTransitionType.move,
                duration: TimelineDuration.fromMicroseconds(5000000),
                easing: CameraEasing.easeInOut,
              ),
            ),
          ],
        ),
      ],
    );
    final compiled =
        const TimelineCompiler(
          drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
        ).compile(
          document: base.copyWith(
            cameraTrack: track,
            timeline: base.timeline.copyWith(
              camera: PersistentCameraTimelineTrack.enabled(
                cameraTrackId: track.id,
              ),
            ),
          ),
          documentRevision: 7,
        );

    expect(
      compiled.camera!.shots.single.interval.start,
      compiled.drawing!.sections.single.interval.start,
    );
    expect(
      compiled.camera!.shots.single.interval.end,
      compiled.drawing!.sections.single.interval.end,
    );
    expect(
      compiled.camera!.shots.single.segments.last.interval.end,
      compiled.drawing!.sections.single.interval.end,
    );
  });

  test('camera longer than drawing extends duration and drawing holds', () {
    final base = projectDocumentParityFixture();
    final track = ProjectCameraTrack(
      id: CameraTrackId('camera'),
      shots: [
        CameraShot(
          id: CameraShotId('shot'),
          startTime: TimelineTime.zero,
          duration: TimelineDuration.fromMicroseconds(30000000),
          authorship: CameraAuthorship.manual,
          isLocked: false,
          keyframes: [
            CameraKeyframe(
              id: CameraKeyframeId('key'),
              offset: TimelineTime.zero,
              view: const CameraView(centerX: 2, centerY: 3, viewportWidth: .5),
            ),
          ],
        ),
      ],
    );
    final document = base.copyWith(
      cameraTrack: track,
      timeline: base.timeline.copyWith(
        camera: PersistentCameraTimelineTrack.enabled(cameraTrackId: track.id),
      ),
    );
    final compiled = const TimelineCompiler(
      drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
    ).compile(document: document, documentRevision: 4);
    expect(compiled.duration.microseconds, greaterThanOrEqualTo(30000000));
    expect(compiled.camera!.dependencyKey, compiled.dependencyKey);
    final frame = const GlobalTimelineResolver().resolveAt(
      compiled,
      TimelineTime.fromMicroseconds(29999999),
    );
    expect(frame.drawing!.isHeld, isTrue);
    expect((frame.camera as ResolvedSingleCameraView).view.centerX, 2);
  });

  test(
    'disabled camera does not extend duration and still resolves identity',
    () {
      final base = projectDocumentParityFixture();
      final track = ProjectCameraTrack(
        id: CameraTrackId('camera'),
        enabled: false,
        shots: [
          CameraShot(
            id: CameraShotId('shot'),
            startTime: TimelineTime.zero,
            duration: TimelineDuration.fromMicroseconds(30000000),
            authorship: CameraAuthorship.manual,
            isLocked: false,
            keyframes: [
              CameraKeyframe(
                id: CameraKeyframeId('key'),
                offset: TimelineTime.zero,
                view: const CameraView.identity(),
              ),
            ],
          ),
        ],
      );
      final document = base.copyWith(
        cameraTrack: track,
        timeline: base.timeline.copyWith(
          camera: PersistentCameraTimelineTrack.enabled(
            cameraTrackId: track.id,
          ),
        ),
      );
      final compiled = const TimelineCompiler(
        drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
      ).compile(document: document, documentRevision: 1);
      expect(compiled.duration.microseconds, lessThan(30000000));
      expect(
        (const GlobalTimelineResolver()
                    .resolveAt(compiled, TimelineTime.zero)
                    .camera
                as ResolvedSingleCameraView)
            .view,
        const CameraView.identity(),
      );
    },
  );
}
