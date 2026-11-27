import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  testWidgets('clip center drag moves time in one transaction', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(
      TimelineTime.fromDuration(const Duration(seconds: 1)),
    );
    final revision = cubit.state.documentRevision.value;
    final history = cubit.history.undoEntries.length;
    await _pumpDock(tester, cubit);
    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    final gesture = await tester.startGesture(
      tester.getTopLeft(painter) + const Offset(400, 20),
    );
    await gesture.moveBy(const Offset(36, 0));
    await tester.pump();
    expect(cubit.state.documentRevision.value, revision);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
    expect(cubit.state.documentRevision.value, revision + 1);
    expect(cubit.history.undoEntries, hasLength(history + 1));
  });

  testWidgets('Escape cancels a transient clip move', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(
      TimelineTime.fromDuration(const Duration(seconds: 1)),
    );
    final shot = cubit.state.document.cameraTrack!.shots.single;
    final revision = cubit.state.documentRevision;
    await _pumpDock(tester, cubit);
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(const ValueKey('camera-clips-painter'))) +
          const Offset(400, 20),
    );
    await gesture.moveBy(const Offset(50, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(cubit.state.documentRevision, revision);
    expect(
      cubit.state.document.cameraTrack!.shots.single.startTime,
      shot.startTime,
    );
  });

  testWidgets('selecting a clip restores its exact saved target view', (
    tester,
  ) async {
    final cubit = EditorCubit();
    final editing = CameraEditingCubit();
    addTearDown(cubit.close);
    addTearDown(editing.close);
    const saved = CameraView(centerX: .23, centerY: .81, viewportWidth: .37);
    cubit.addCameraShotAtWithView(
      TimelineTime.fromDuration(const Duration(seconds: 1)),
      saved,
    );
    editing.setEditorView(const CameraView.identity());
    final revision = cubit.state.documentRevision;
    final history = cubit.history.undoEntries.length;
    await _pumpDock(tester, cubit, cameraEditing: editing);

    final shot = cubit.state.document.cameraTrack!.shots.single;
    await tester.tapAt(_clipCenter(tester, cubit, shot));
    await tester.pump(const Duration(milliseconds: 400));

    expect(editing.state.editorView, saved);
    expect(editing.state.savedEditorView, saved);
    expect(editing.state.isEditorViewDirty, isFalse);
    expect(editing.state.canvasMode, CameraCanvasMode.editCamera);
    expect(cubit.state.documentRevision, revision);
    expect(cubit.history.undoEntries, hasLength(history));
  });

  testWidgets('double click restores the view and opens shot properties', (
    tester,
  ) async {
    final cubit = EditorCubit();
    final editing = CameraEditingCubit();
    double? seek;
    addTearDown(cubit.close);
    addTearDown(editing.close);
    const saved = CameraView(centerX: .7, centerY: .4, viewportWidth: .42);
    cubit.addCameraShotAtWithView(
      TimelineTime.fromDuration(const Duration(seconds: 1)),
      saved,
    );
    await _pumpDock(
      tester,
      cubit,
      cameraEditing: editing,
      onSeek: (value) => seek = value,
    );
    final shot = cubit.state.document.cameraTrack!.shots.single;
    final point = _clipCenter(tester, cubit, shot);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.state.editorView, saved);
    expect(seek, isNotNull);
    expect(
      find.byKey(const ValueKey('camera-shot-properties-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('dragging a selected clip edge resizes it in one transaction', (
    tester,
  ) async {
    final cubit = EditorCubit();
    final editing = CameraEditingCubit();
    addTearDown(cubit.close);
    addTearDown(editing.close);
    cubit.addCameraShotAtWithView(
      TimelineTime.fromDuration(const Duration(seconds: 1)),
      const CameraView.identity(),
    );
    await _pumpDock(tester, cubit, cameraEditing: editing);
    final shot = cubit.state.document.cameraTrack!.shots.single;
    final revision = cubit.state.documentRevision.value;
    final history = cubit.history.undoEntries.length;
    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    final painterRect = tester.getRect(painter);
    final timelineUs = cubit.compileTimeline().duration.microseconds;
    final right =
        painterRect.left +
        shot.endTime.microseconds / timelineUs * painterRect.width;
    final gesture = await tester.startGesture(
      Offset(right - 2, painterRect.center.dy),
    );
    await gesture.moveBy(const Offset(28, 0));
    await tester.pump();
    expect(cubit.state.documentRevision.value, revision);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));
    expect(cubit.state.documentRevision.value, revision + 1);
    expect(cubit.history.undoEntries, hasLength(history + 1));
    expect(
      cubit.state.document.cameraTrack!.shots.single.duration.microseconds,
      greaterThan(shot.duration.microseconds),
    );
  });

  testWidgets(
    'left trim handle highlights and expands the shot while preserving its end',
    (tester) async {
      final cubit = EditorCubit();
      final editing = CameraEditingCubit();
      addTearDown(cubit.close);
      addTearDown(editing.close);
      cubit.addCameraShotAtWithView(
        TimelineTime.fromDuration(const Duration(seconds: 1)),
        const CameraView.identity(),
      );
      await _pumpDock(tester, cubit, cameraEditing: editing);
      final original = cubit.state.document.cameraTrack!.shots.single;
      final originalEnd = original.endTime;
      final revision = cubit.state.documentRevision.value;
      final history = cubit.history.undoEntries.length;
      final painter = find.byKey(const ValueKey('camera-clips-painter'));
      final painterRect = tester.getRect(painter);
      final timelineUs = cubit.compileTimeline().duration.microseconds;
      final left =
          painterRect.left +
          original.startTime.microseconds / timelineUs * painterRect.width;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: Offset(left - 30, painterRect.center.dy),
      );
      await mouse.moveTo(Offset(left + 1, painterRect.center.dy));
      await tester.pump();
      expect(
        tester
            .widget<MouseRegion>(
              find.byKey(const ValueKey('camera-clips-mouse-region')),
            )
            .cursor,
        SystemMouseCursors.resizeLeftRight,
      );

      final drag = await tester.startGesture(
        Offset(left + 1, painterRect.center.dy),
      );
      await drag.moveBy(const Offset(-36, 0));
      await tester.pump();
      expect(
        editing.state.interactionMode,
        CameraInteractionMode.trimmingStart,
      );
      expect(cubit.state.documentRevision.value, revision);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 80));

      final resized = cubit.state.document.cameraTrack!.shots.single;
      expect(resized.startTime.compareTo(original.startTime), lessThan(0));
      expect(resized.endTime, originalEnd);
      expect(cubit.state.documentRevision.value, revision + 1);
      expect(cubit.history.undoEntries, hasLength(history + 1));
      await mouse.removePointer();
    },
  );

  testWidgets('Undo of Update restores the selected editor view', (
    tester,
  ) async {
    final cubit = EditorCubit();
    final editing = CameraEditingCubit();
    addTearDown(cubit.close);
    addTearDown(editing.close);
    const before = CameraView(centerX: .4, centerY: .6, viewportWidth: .7);
    const after = CameraView(centerX: .8, centerY: .2, viewportWidth: .3);
    cubit.addCameraShotAtWithView(TimelineTime.zero, before);
    final shot = cubit.state.document.cameraTrack!.shots.single;
    await _pumpDock(tester, cubit, cameraEditing: editing);
    editing.selectKeyframe(shot.id, shot.keyframes.single.id);
    editing.restoreEditorView(before);
    cubit.setCameraKeyframeView(shot.id, shot.keyframes.single.id, after);
    editing.restoreEditorView(after);
    cubit.undoStroke();
    await tester.pump();
    expect(editing.state.editorView, before);
    expect(editing.state.savedEditorView, before);
  });

  testWidgets('timeline exposes clips without Advanced or Start End controls', (
    tester,
  ) async {
    final cubit = EditorCubit();
    final editing = CameraEditingCubit();
    addTearDown(cubit.close);
    addTearDown(editing.close);
    await _pumpDock(tester, cubit, cameraEditing: editing);
    expect(find.textContaining('Compose the view above'), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-shot-inspector')), findsNothing);
    expect(find.byKey(const ValueKey('camera-track-enabled')), findsNothing);
    expect(find.byKey(const ValueKey('camera-auto-director')), findsNothing);
    expect(find.textContaining('Advanced'), findsNothing);
    expect(find.textContaining('Start view'), findsNothing);
    expect(find.textContaining('End view'), findsNothing);
  });
}

Offset _clipCenter(WidgetTester tester, EditorCubit cubit, CameraShot shot) {
  final rect = tester.getRect(
    find.byKey(const ValueKey('camera-clips-painter')),
  );
  final timelineUs = cubit.compileTimeline().duration.microseconds;
  final centerUs = shot.startTime.microseconds + shot.duration.microseconds / 2;
  return Offset(rect.left + centerUs / timelineUs * rect.width, rect.center.dy);
}

Future<void> _pumpDock(
  WidgetTester tester,
  EditorCubit cubit, {
  CameraEditingCubit? cameraEditing,
  ValueChanged<double>? onSeek,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 420));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: EditorTimelineDock(
            cubit: cubit,
            previewProgress: 0,
            isPreviewing: false,
            onSeek: onSeek ?? (_) {},
            onPreviewStroke: (_) {},
            onTimingChangeStart: () {},
            onTimingChangeEnd: () {},
            playheadTime: TimelineTime.zero,
            cameraEditing: cameraEditing,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
