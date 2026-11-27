import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/camera/presentation/editor_viewport.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('each added clip stores one user view through a compatible adapter', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    const first = CameraView(centerX: .5, centerY: .5, viewportWidth: 1);
    const second = CameraView(centerX: .2, centerY: .3, viewportWidth: .4);
    expect(editor.addCameraShotAtWithView(TimelineTime.zero, first), isTrue);
    expect(
      editor.addCameraShotAtWithView(
        TimelineTime.fromDuration(const Duration(seconds: 2)),
        second,
      ),
      isTrue,
    );
    final shots = editor.state.document.cameraTrack!.shots;
    expect(shots, hasLength(2));
    expect(shots.first.keyframes.single.view, first);
    expect(shots.last.keyframes, hasLength(2));
    expect(shots.last.keyframes.map((frame) => frame.view).toSet(), {second});
    expect(
      editor.updateSimpleCameraView(
        shots.last.id,
        const CameraView(centerX: .8, centerY: .6, viewportWidth: .3),
      ),
      isTrue,
    );
    expect(
      editor.state.document.cameraTrack!.shots.last.keyframes
          .map((frame) => frame.view)
          .toSet(),
      {const CameraView(centerX: .8, centerY: .6, viewportWidth: .3)},
    );
  });

  test('timing properties update transition and hold in one history step', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    editor.addCameraShotAtWithView(
      TimelineTime.zero,
      const CameraView.identity(),
    );
    final shot = editor.state.document.cameraTrack!.shots.single;
    final beforeRevision = editor.state.documentRevision.value;
    final beforeHistory = editor.history.undoEntries.length;
    expect(
      editor.updateSimpleCameraViewTiming(
        shotId: shot.id,
        movement: SimpleCameraMovement.ease,
        movementDuration: TimelineDuration.fromMicroseconds(600000),
        holdDuration: TimelineDuration.fromMicroseconds(1400000),
      ),
      isTrue,
    );
    final updated = editor.state.document.cameraTrack!.shots.single;
    expect(updated.keyframes, hasLength(2));
    expect(updated.keyframes.first.view, updated.keyframes.last.view);
    expect(updated.duration.microseconds, 2000000);
    expect(
      updated.keyframes.last.incomingTransition.type,
      CameraTransitionType.move,
    );
    expect(
      updated.keyframes.last.incomingTransition.easing,
      CameraEasing.easeInOut,
    );
    expect(editor.state.documentRevision.value, beforeRevision + 1);
    expect(editor.history.undoEntries, hasLength(beforeHistory + 1));
    editor.undoStroke();
    expect(
      editor
          .state
          .document
          .cameraTrack!
          .shots
          .single
          .keyframes
          .single
          .incomingTransition
          .type,
      CameraTransitionType.cut,
    );
    editor.redoStroke();
    expect(
      editor.state.document.cameraTrack!.shots.single.duration.microseconds,
      2000000,
    );
  });

  test('Zoom In then Out replaces one shot atomically with three views', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    editor.addCameraShotAtWithView(
      TimelineTime.zero,
      const CameraView.identity(),
    );
    final source = editor.state.document.cameraTrack!.shots.single;
    editor.updateSimpleCameraViewTiming(
      shotId: source.id,
      movement: SimpleCameraMovement.cut,
      movementDuration: TimelineDuration.zero,
      holdDuration: TimelineDuration.fromMicroseconds(6000000),
    );
    final sourceBeforePreset = editor.state.document.cameraTrack!.shots.single;
    final revision = editor.state.documentRevision.value;
    final history = editor.history.undoEntries.length;

    expect(
      editor.applyCameraZoomInOutPreset(
        sourceShotId: sourceBeforePreset.id,
        startTime: sourceBeforePreset.startTime,
        totalDuration: sourceBeforePreset.duration,
        focusView: const CameraView(
          centerX: .3,
          centerY: .65,
          viewportWidth: 1,
        ),
        strength: 2,
        zoomInDuration: TimelineDuration.fromMicroseconds(800000),
        zoomOutDuration: TimelineDuration.fromMicroseconds(700000),
      ),
      isTrue,
    );

    final shots = editor.state.document.cameraTrack!.shots;
    expect(shots, hasLength(3));
    expect(shots.map((shot) => shot.label), ['Wide', 'Zoom In', 'Zoom Out']);
    expect(shots.first.startTime, sourceBeforePreset.startTime);
    expect(shots.last.endTime, sourceBeforePreset.endTime);
    expect(shots[0].endTime, shots[1].startTime);
    expect(shots[1].endTime, shots[2].startTime);
    expect(
      shots[1].keyframes.last.view,
      const CameraView(centerX: .3, centerY: .65, viewportWidth: .5),
    );
    expect(
      shots[1].keyframes.last.incomingTransition.duration.microseconds,
      800000,
    );
    expect(
      shots[2].keyframes.last.incomingTransition.duration.microseconds,
      700000,
    );
    expect(editor.state.documentRevision.value, revision + 1);
    expect(editor.history.undoEntries, hasLength(history + 1));

    editor.undoStroke();
    expect(editor.state.document.cameraTrack!.shots, [sourceBeforePreset]);
    editor.redoStroke();
    expect(editor.state.document.cameraTrack!.shots, hasLength(3));
  });

  testWidgets('EditorViewport uses output bounds, independent of side panels', (
    tester,
  ) async {
    const view = CameraView(centerX: .3, centerY: .7, viewportWidth: .5);
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            SizedBox(width: 180),
            SizedBox(
              width: 400,
              height: 225,
              child: EditorViewport(
                view: view,
                child: ColoredBox(color: Colors.red),
              ),
            ),
            SizedBox(width: 320),
            SizedBox(
              width: 400,
              height: 225,
              child: EditorViewport(
                view: view,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
    final transforms = tester
        .widgetList<Transform>(
          find.byKey(const ValueKey('camera-editor-viewport-transform')),
        )
        .toList();
    expect(transforms, hasLength(2));
    expect(
      transforms.first.transform.storage,
      transforms.last.transform.storage,
    );
    expect(
      tester.getSize(find.byType(EditorViewport).first),
      const Size(400, 225),
    );
  });

  test('project output aspect determines normalized camera height', () {
    const view = CameraView(centerX: .5, centerY: .5, viewportWidth: .5);
    expect(
      view.normalizedViewportHeightFor(
        projectAspectRatio: 16 / 9,
        outputAspectRatio: 16 / 9,
      ),
      .5,
    );
    expect(
      view.normalizedViewportHeightFor(
        projectAspectRatio: 9 / 16,
        outputAspectRatio: 9 / 16,
      ),
      .5,
    );
  });

  test('camera edit keeps the raw scene fixed and crops only output', () {
    final viewport = File(
      'lib/features/camera/presentation/editor_viewport.dart',
    ).readAsStringSync();
    final canvas = File(
      'lib/features/editor/presentation/widgets/editor_canvas.dart',
    ).readAsStringSync();
    expect(viewport, isNot(contains('CameraVisualCompositor')));
    expect(canvas, isNot(contains('EditorViewport(')));
    expect(canvas, contains('final rawEditorScene = Stack('));
    expect(canvas, contains('CameraCanvasOverlay('));
    expect(canvas, contains('if (cameraOutputPreview)'));
  });
}
