import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test(
    'camera editing does not capture canvas drags until move mode is chosen',
    () {
      final cubit = CameraEditingCubit();
      expect(cubit.state.canvasMode, CameraCanvasMode.editCamera);
      cubit.setCanvasMode(CameraCanvasMode.browse);
      expect(cubit.state.canvasMode, CameraCanvasMode.browse);
      cubit.close();
    },
  );

  test('timeline frame visibility alone never enables camera output', () {
    final state = CameraEditingState(canvasMode: CameraCanvasMode.editCamera);
    expect(state.cameraOutputEnabled(timelineFrameVisible: true), isFalse);
    expect(
      state
          .copyWith(canvasMode: CameraCanvasMode.previewCamera)
          .cameraOutputEnabled(timelineFrameVisible: true),
      isTrue,
    );
  });

  test(
    'new-shot timing defaults stay view-only and survive selection clear',
    () {
      final cubit = CameraEditingCubit();
      const defaults = CameraShotDefaults(
        movement: SimpleCameraMovement.linear,
        movementDuration: Duration(milliseconds: 800),
        holdDuration: Duration(milliseconds: 1700),
      );
      cubit.setShotDefaults(defaults);
      cubit.clear();
      expect(cubit.state.shotDefaults, same(defaults));
      cubit.close();
    },
  );

  test('new camera shots consume the chosen timing defaults independently', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    final move = TimelineDuration.fromDuration(
      const Duration(milliseconds: 800),
    );
    final hold = TimelineDuration.fromDuration(
      const Duration(milliseconds: 1700),
    );
    expect(
      editor.addCameraShotAtWithView(
        TimelineTime.zero,
        const CameraView.identity(),
        movement: SimpleCameraMovement.linear,
        movementDuration: move,
        holdDuration: hold,
      ),
      isTrue,
    );
    expect(
      editor.addCameraShotAtWithView(
        TimelineTime.fromDuration(const Duration(seconds: 3)),
        const CameraView(centerX: .4, centerY: .4, viewportWidth: .7),
        movement: SimpleCameraMovement.linear,
        movementDuration: move,
        holdDuration: hold,
      ),
      isTrue,
    );
    final shots = editor.state.document.cameraTrack!.shots;
    expect(shots, hasLength(2));
    expect(shots[1].duration.microseconds, 2500000);
    expect(
      shots[1].keyframes.last.incomingTransition.easing,
      CameraEasing.linear,
    );
    expect(
      shots[1].keyframes.last.incomingTransition.duration.microseconds,
      800000,
    );
  });
  final shots = [_shot('a', 0), _shot('b', 2), _shot('c', 4)];

  test('selection, toggle, range and reconciliation stay outside document', () {
    final cubit = CameraEditingCubit();
    cubit.select(shots.first.id, shots: shots);
    cubit.select(shots.last.id, range: true, shots: shots);
    expect(cubit.state.selectedShotIds, shots.map((shot) => shot.id).toSet());

    cubit.select(shots[1].id, toggle: true, shots: shots);
    expect(cubit.state.selectedShotIds, isNot(contains(shots[1].id)));
    cubit.reconcile([shots.last.id]);
    expect(cubit.state.selectedShotIds, {shots.last.id});
    cubit.close();
  });

  test(
    'primary shot selects its first keyframe and canvas preferences survive clear',
    () {
      final cubit = CameraEditingCubit();
      cubit.setCanvasMode(CameraCanvasMode.editCamera);
      cubit.setFrameVisibility(CameraFrameVisibility.allPinned);
      cubit.setFollowPlayhead(true);
      cubit.select(shots.first.id, shots: shots);
      cubit.selectKeyframe(shots.first.id, shots.first.keyframes.first.id);
      expect(cubit.state.selectedKeyframeId, shots.first.keyframes.first.id);
      cubit.togglePinned(shots.first.keyframes.first.id);
      cubit.clear();
      expect(cubit.state.canvasMode, CameraCanvasMode.editCamera);
      expect(cubit.state.frameVisibility, CameraFrameVisibility.allPinned);
      expect(cubit.state.followPlayhead, isTrue);
      expect(
        cubit.state.pinnedKeyframeIds,
        contains(shots.first.keyframes.first.id),
      );
      cubit.close();
    },
  );

  test('drag remains transient and cancellation restores idle state', () {
    final cubit = CameraEditingCubit();
    cubit.begin(shots.first, CameraInteractionMode.moving);
    cubit.update(
      cubit.state.transientEdit!.copyWith(
        previewStart: TimelineTime.fromMicroseconds(500000),
      ),
    );
    expect(cubit.state.transientEdit!.previewStart.microseconds, 500000);
    cubit.cancelInteraction();
    expect(cubit.state.interactionMode, CameraInteractionMode.idle);
    expect(cubit.state.transientEdit, isNull);
    cubit.close();
  });

  test('keyframe inspector operation edits only the selected keyframe', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    editor.addCameraShotAt(TimelineTime.zero);
    final shotId = editor.state.document.cameraTrack!.shots.single.id;
    editor.addCameraKeyframe(
      shotId,
      TimelineTime.fromDuration(const Duration(milliseconds: 500)),
      const CameraView(centerX: .4, centerY: .5, viewportWidth: .8),
    );
    editor.addCameraKeyframe(
      shotId,
      TimelineTime.fromDuration(const Duration(milliseconds: 1500)),
      const CameraView(centerX: .7, centerY: .5, viewportWidth: .5),
    );
    final before = editor.state.document.cameraTrack!.shots.single.keyframes;
    final selected = before[1];
    final untouched = before[2];
    editor.updateCameraKeyframeInspector(
      shotId: shotId,
      keyframeId: selected.id,
      offset: TimelineTime.fromDuration(const Duration(milliseconds: 700)),
      transition: CameraTransition(
        type: CameraTransitionType.move,
        duration: TimelineDuration.fromDuration(
          const Duration(milliseconds: 200),
        ),
        easing: CameraEasing.easeOut,
      ),
    );
    final after = editor.state.document.cameraTrack!.shots.single.keyframes;
    expect(after.singleWhere((frame) => frame.id == untouched.id), untouched);
    final edited = after.singleWhere((frame) => frame.id == selected.id);
    expect(edited.offset.microseconds, 700000);
    expect(edited.incomingTransition.type, CameraTransitionType.move);
  });
}

CameraShot _shot(String id, int seconds) => CameraShot(
  id: CameraShotId(id),
  startTime: TimelineTime.fromDuration(Duration(seconds: seconds)),
  duration: TimelineDuration.fromDuration(const Duration(seconds: 1)),
  authorship: CameraAuthorship.auto,
  isLocked: false,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('kf-$id'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);
