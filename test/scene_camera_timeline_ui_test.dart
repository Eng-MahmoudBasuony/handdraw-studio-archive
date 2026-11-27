import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  testWidgets('scene placeholder creates one aligned three-view camera clip', (
    tester,
  ) async {
    final project = HandDrawProject(
      durationSeconds: 6,
      drawingDurationSeconds: 6,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'stroke-a',
          name: 'Artwork A',
          points: const [Offset(.1, .1), Offset(.9, .9)],
          sectionId: 'section-a',
        ),
      ],
      timelineSectionOrder: const ['section-a'],
      sceneGroups: [
        DrawingSceneGroup(
          id: 'scene-a',
          name: 'Scene A',
          sectionIds: const ['section-a'],
        ),
      ],
    );
    final editor = EditorCubit(initialState: testEditorState(project: project));
    final editing = CameraEditingCubit();
    addTearDown(editor.close);
    addTearDown(editing.close);
    expect(editor.ensureSceneCameraClip(SceneId('scene-a')), isTrue);
    expect(editor.state.document.cameraTrack, isNotNull);
    editor.undoStroke();
    expect(editor.state.document.cameraTrack, isNull);
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    TimelineTime? soughtTime;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorTimelineDock(
            cubit: editor,
            cameraEditing: editing,
            previewProgress: 0,
            isPreviewing: false,
            onSeek: (progress) {
              soughtTime = TimelineTime.fromMicroseconds(
                (progress * 6000000).round(),
              );
            },
            onPreviewStroke: (_) {},
            onTimingChangeStart: () {},
            onTimingChangeEnd: () {},
            playheadTime: TimelineTime.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(editor.state.document.cameraTrack, isNull);
    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    expect(painter, findsOneWidget);
    await tester.tapAt(tester.getCenter(painter));
    await tester.pumpAndSettle();

    final clip = editor.state.document.cameraTrack!.shots.single;
    expect(clip.ownerSceneId?.value, 'scene-a');
    expect(clip.keyframes, hasLength(3));
    expect(clip.startTime, TimelineTime.zero);
    expect(clip.duration.microseconds, 6000000);
    expect(editing.state.primaryShotId, clip.id);
    expect(editing.state.selectedKeyframeId, clip.keyframes.first.id);
    expect(editing.state.canvasMode, CameraCanvasMode.editCamera);
    expect(soughtTime, clip.startTime);
  });

  testWidgets('artwork and camera timeline blocks drive the viewer position', (
    tester,
  ) async {
    final project = HandDrawProject(
      durationSeconds: 6,
      drawingDurationSeconds: 6,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'stroke-a',
          name: 'Artwork A',
          points: const [Offset(.1, .1), Offset(.9, .9)],
          sectionId: 'section-a',
        ),
      ],
      timelineSectionOrder: const ['section-a'],
    );
    final editor = EditorCubit(initialState: testEditorState(project: project));
    final editing = CameraEditingCubit();
    addTearDown(editor.close);
    addTearDown(editing.close);
    const cameraView = CameraView(centerX: .35, centerY: .6, viewportWidth: .5);
    expect(
      editor.addCameraShotAtWithView(
        TimelineTime.fromMicroseconds(2000000),
        cameraView,
      ),
      isTrue,
    );
    final shot = editor.state.document.cameraTrack!.shots.single;
    final savedCameraView = shot.keyframes.last.view;
    double? soughtProgress;
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorTimelineDock(
            cubit: editor,
            cameraEditing: editing,
            previewProgress: 0,
            isPreviewing: false,
            onSeek: (progress) => soughtProgress = progress,
            onPreviewStroke: (_) {},
            onTimingChangeStart: () {},
            onTimingChangeEnd: () {},
            playheadTime: TimelineTime.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    editing.setCanvasMode(CameraCanvasMode.editCamera);
    await tester.tap(
      find.byKey(const ValueKey('timeline-thumbnail-section-a')),
    );
    await tester.pump();

    final range = editor.timelineSectionRanges['section-a']!;
    final durationUs = editor.compileTimeline().duration.microseconds;
    expect(editor.selectedStrokeIndex, 0);
    expect(editing.state.canvasMode, CameraCanvasMode.browse);
    expect(
      soughtProgress,
      closeTo(
        (range.endSeconds * Duration.microsecondsPerSecond - 1) / durationUs,
        0.000001,
      ),
    );

    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    final painterRect = tester.getRect(painter);
    final shotCenterSeconds =
        (shot.startTime.microseconds + shot.duration.microseconds / 2) /
        Duration.microsecondsPerSecond;
    await tester.tapAt(
      Offset(
        painterRect.left +
            painterRect.width *
                shotCenterSeconds /
                (durationUs / Duration.microsecondsPerSecond),
        painterRect.center.dy,
      ),
    );
    await tester.pumpAndSettle();

    expect(editing.state.primaryShotId, shot.id);
    expect(editing.state.selectedKeyframeId, shot.keyframes.last.id);
    expect(editing.state.editorView.centerX, savedCameraView.centerX);
    expect(editing.state.editorView.centerY, savedCameraView.centerY);
    expect(
      editing.state.editorView.viewportWidth,
      savedCameraView.viewportWidth,
    );
    expect(editing.state.canvasMode, CameraCanvasMode.editCamera);
    expect(
      soughtProgress,
      closeTo(shot.startTime.microseconds / durationUs, 0.000001),
    );
  });

  testWidgets('selecting a camera frame does not impersonate active playback', (
    tester,
  ) async {
    final image = await _solidImage();
    final project = HandDrawProject(
      drawingImagePath: '/tmp/camera-player.png',
      durationSeconds: 6,
      drawingDurationSeconds: 6,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'stroke-a',
          name: 'Artwork A',
          points: const [Offset(.1, .1), Offset(.9, .9)],
          sectionId: 'section-a',
        ),
      ],
      timelineSectionOrder: const ['section-a'],
    );
    final editor = EditorCubit(
      initialState: testEditorState(project: project, drawingImage: image),
    );
    addTearDown(() {
      editor.close();
      image.dispose();
    });
    expect(
      editor.addCameraShotAtWithView(
        TimelineTime.fromMicroseconds(2000000),
        const CameraView(centerX: .4, centerY: .55, viewportWidth: .5),
      ),
      isTrue,
    );
    final shot = editor.state.document.cameraTrack!.shots.single;
    expect(editor.canPreview, isTrue);
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: editor)));
    await tester.pumpAndSettle();

    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    final painterRect = tester.getRect(painter);
    final durationUs = editor.compileTimeline().duration.microseconds;
    final shotCenterUs =
        shot.startTime.microseconds + shot.duration.microseconds / 2;
    await tester.tapAt(
      Offset(
        painterRect.left + painterRect.width * shotCenterUs / durationUs,
        painterRect.center.dy,
      ),
    );
    await tester.pumpAndSettle();

    IconData playerIcon() =>
        (tester
                    .widget<IconButton>(
                      find.byKey(const ValueKey('canvas-preview-toggle')),
                    )
                    .icon
                as Icon)
            .icon!;
    expect(playerIcon(), Icons.play_arrow);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('canvas-preview-toggle')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('canvas-preview-stop')), findsNothing);
  });

  testWidgets('dragging the global ruler scrubs the viewer and playhead', (
    tester,
  ) async {
    final image = await _solidImage();
    final project = HandDrawProject(
      drawingImagePath: '/tmp/global-scrub.png',
      durationSeconds: 8,
      drawingDurationSeconds: 8,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'stroke-a',
          name: 'Artwork A',
          points: const [Offset(.1, .1), Offset(.9, .9)],
          sectionId: 'section-a',
        ),
      ],
      timelineSectionOrder: const ['section-a'],
    );
    final editor = EditorCubit(
      initialState: testEditorState(project: project, drawingImage: image),
    );
    addTearDown(() {
      editor.close();
      image.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: editor)));
    await tester.pumpAndSettle();

    final ruler = find.byKey(const ValueKey('timeline-ruler'));
    final rulerRect = tester.getRect(ruler);
    final gesture = await tester.startGesture(
      Offset(rulerRect.left + rulerRect.width * .15, rulerRect.center.dy),
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      Offset(rulerRect.left + rulerRect.width * .72, rulerRect.center.dy),
    );
    await tester.pumpAndSettle();

    final viewerProgress = tester.widget<Slider>(
      find.byKey(const ValueKey('canvas-preview-progress')),
    );
    expect(viewerProgress.value, closeTo(.72, .02));
    expect(find.byKey(const ValueKey('timeline-playhead')), findsOneWidget);
    expect(
      (tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('canvas-preview-toggle')),
                  )
                  .icon
              as Icon)
          .icon,
      Icons.play_arrow,
    );
    await gesture.up();

    await tester.drag(
      find.byKey(const ValueKey('timeline-playhead')),
      Offset(-rulerRect.width * .2, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('canvas-preview-progress')))
          .value,
      closeTo(.52, .03),
    );
  });

  testWidgets('canvas focus mode gives the viewer priority and is reversible', (
    tester,
  ) async {
    final image = await _solidImage();
    final project = HandDrawProject(
      drawingImagePath: '/tmp/canvas-focus.png',
      durationSeconds: 6,
      drawingDurationSeconds: 6,
      strokes: [
        DrawingStroke(
          id: 'stroke-a',
          name: 'Artwork A',
          points: const [Offset(.1, .1), Offset(.9, .9)],
          sectionId: 'section-a',
        ),
      ],
      timelineSectionOrder: const ['section-a'],
    );
    final editor = EditorCubit(
      initialState: testEditorState(project: project, drawingImage: image),
    );
    addTearDown(() {
      editor.close();
      image.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: editor)));
    await tester.pumpAndSettle();

    final viewer = find.byKey(const ValueKey('project-video-aspect-ratio'));
    final before = tester.getSize(viewer);
    expect(find.byKey(const ValueKey('editor-timeline-dock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('close-inspector')),
        matching: find.byIcon(Icons.keyboard_double_arrow_right_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('close-inspector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-inspector-docked')), findsNothing);
    expect(
      find.byKey(const ValueKey('editor-inspector-collapsed')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open-collapsed-inspector')),
        matching: find.byIcon(Icons.keyboard_double_arrow_left_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('open-collapsed-inspector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );

    final timeline = find.byKey(const ValueKey('editor-timeline-dock'));
    final timelineBefore = tester.getSize(timeline).height;
    await tester.drag(
      find.byKey(const ValueKey('timeline-resize-handle')),
      const Offset(0, -30),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(timeline).height, greaterThan(timelineBefore));

    await tester.tap(find.byKey(const ValueKey('canvas-focus-mode-toggle')));
    await tester.pumpAndSettle();

    final focused = tester.getSize(viewer);
    expect(focused.width, greaterThan(before.width));
    expect(focused.height, greaterThan(before.height));
    expect(find.byKey(const ValueKey('editor-timeline-dock')), findsNothing);
    expect(find.byKey(const ValueKey('editor-inspector-docked')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('canvas-focus-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-timeline-dock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );
  });
}

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 32, 32),
    ui.Paint()..color = Colors.white,
  );
  return recorder.endRecording().toImage(32, 32);
}
