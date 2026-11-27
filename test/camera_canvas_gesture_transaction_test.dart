import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/application/camera_editor_view_commit_service.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_overlay.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_shot_properties_dialog.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_viewport_frame.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_workspace.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/unified_project_frame_resolver.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  testWidgets('editor pan stays view-only until Add Camera', (tester) async {
    final fixture = await _pumpOverlay(tester, withShot: false);
    final document = fixture.editor.state.document;
    final revision = fixture.editor.state.documentRevision;
    final history = fixture.editor.history.undoEntries.length;

    final surface = find.byKey(
      const ValueKey('camera-editor-view-gesture-surface'),
    );
    final pan = await tester.startGesture(
      tester.getCenter(surface),
      buttons: kMiddleMouseButton,
    );
    await pan.moveBy(const Offset(120, 45));
    await pan.up();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(surface),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();

    expect(
      fixture.editing.state.editorView,
      isNot(const CameraView.identity()),
    );
    expect(fixture.editing.state.editorView.viewportWidth, lessThan(1));
    expect(fixture.editor.state.document, same(document));
    expect(fixture.editor.state.documentRevision, revision);
    expect(fixture.editor.history.undoEntries, hasLength(history));
  });

  testWidgets('Add Camera saves the exact current editor view atomically', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester, withShot: false);
    const composed = CameraView(centerX: .31, centerY: .72, viewportWidth: .44);
    fixture.editing.setEditorView(composed);
    await tester.pump();
    final revision = fixture.editor.state.documentRevision.value;
    final history = fixture.editor.history.undoEntries.length;

    await tester.tap(find.byKey(const ValueKey('camera-add-current-view')));
    await tester.pump();

    final shot = fixture.editor.state.document.cameraTrack!.shots.single;
    expect(shot.keyframes, hasLength(1));
    expect(shot.keyframes.single.view, composed);
    expect(fixture.editing.state.editorView, composed);
    expect(fixture.editing.state.isEditorViewDirty, isFalse);
    expect(fixture.editor.state.documentRevision.value, revision + 1);
    expect(fixture.editor.history.undoEntries, hasLength(history + 1));
    fixture.editor.undoStroke();
    expect(fixture.editor.state.document.cameraTrack, isNull);
    fixture.editor.redoStroke();
    expect(
      fixture
          .editor
          .state
          .document
          .cameraTrack!
          .shots
          .single
          .keyframes
          .single
          .view,
      composed,
    );
  });

  testWidgets('Update is disabled until the restored view changes', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    final update = find.byKey(const ValueKey('camera-update-current-view'));
    expect(tester.widget<OutlinedButton>(update).onPressed, isNull);
    final original = _view(fixture.editor);
    final revision = fixture.editor.state.documentRevision.value;

    await tester.drag(
      find.byKey(const ValueKey('camera-editor-view-gesture-surface')),
      const Offset(80, -25),
    );
    await tester.pump();
    expect(fixture.editing.state.isEditorViewDirty, isTrue);
    expect(tester.widget<OutlinedButton>(update).onPressed, isNotNull);
    expect(_view(fixture.editor), original);
    expect(fixture.editor.state.documentRevision.value, revision);

    await tester.tap(update);
    await tester.pump();
    final updated = _view(fixture.editor);
    expect(updated, fixture.editing.state.editorView);
    expect(updated, isNot(original));
    expect(fixture.editing.state.isEditorViewDirty, isFalse);
    fixture.editor.undoStroke();
    expect(_view(fixture.editor), original);
    fixture.editor.redoStroke();
    expect(_view(fixture.editor), updated);
  });

  testWidgets('master preview commits the exact visible camera frame once', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    const visibleFrame = CameraView(
      centerX: .68,
      centerY: .31,
      viewportWidth: .42,
    );
    fixture.editing.setEditorView(visibleFrame);
    final revision = fixture.editor.state.documentRevision.value;
    final history = fixture.editor.history.undoEntries.length;

    final committed = const CameraEditorViewCommitService().commitIfDirty(
      editor: fixture.editor,
      editing: fixture.editing,
    );

    expect(committed, isTrue);
    expect(_view(fixture.editor), visibleFrame);
    expect(fixture.editing.state.savedEditorView, visibleFrame);
    expect(fixture.editing.state.isEditorViewDirty, isFalse);
    expect(fixture.editor.state.documentRevision.value, revision + 1);
    expect(fixture.editor.history.undoEntries, hasLength(history + 1));
    final resolved = const UnifiedProjectFrameResolver().resolveForPreview(
      fixture.editor.compileTimeline(),
      TimelineTime.zero,
    );
    expect((resolved.camera as ResolvedSingleCameraView).view, visibleFrame);

    expect(
      const CameraEditorViewCommitService().commitIfDirty(
        editor: fixture.editor,
        editing: fixture.editing,
      ),
      isTrue,
    );
    expect(fixture.editor.state.documentRevision.value, revision + 1);
    expect(fixture.editor.history.undoEntries, hasLength(history + 1));
  });

  testWidgets('corner resize preserves aspect and Preview commits it once', (
    tester,
  ) async {
    CameraShot? previewed;
    final fixture = await _pumpOverlay(
      tester,
      onPreviewShot: (shot) => previewed = shot,
    );
    final before = _view(fixture.editor);
    final revision = fixture.editor.state.documentRevision.value;
    final history = fixture.editor.history.undoEntries.length;

    await tester.drag(
      find.byKey(const ValueKey('camera-resize-bottomRight')),
      const Offset(80, 40),
    );
    await tester.pump();

    final transient = fixture.editing.state.editorView;
    expect(transient.viewportWidth, greaterThan(before.viewportWidth));
    expect(transient.centerX, greaterThan(before.centerX));
    expect(transient.centerY, greaterThan(before.centerY));
    expect(_view(fixture.editor), before);

    await tester.tap(find.byKey(const ValueKey('camera-preview-current-view')));
    await tester.pumpAndSettle();

    expect(_view(fixture.editor), transient);
    expect(previewed?.keyframes.single.view, transient);
    expect(fixture.editor.state.documentRevision.value, revision + 1);
    expect(fixture.editor.history.undoEntries, hasLength(history + 1));
  });

  testWidgets(
    'side handle resizes from that edge and anchors the opposite edge',
    (tester) async {
      final fixture = await _pumpOverlay(tester);
      final before = fixture.editing.state.editorView;
      final oldLeft = before.centerX - before.viewportWidth / 2;

      await tester.drag(
        find.byKey(const ValueKey('camera-resize-right')),
        const Offset(80, 0),
      );
      await tester.pump();

      final resized = fixture.editing.state.editorView;
      expect(resized.viewportWidth, greaterThan(before.viewportWidth));
      expect(resized.centerY, before.centerY);
      expect(
        resized.centerX - resized.viewportWidth / 2,
        closeTo(oldLeft, 1e-9),
      );
    },
  );

  testWidgets('Preview warns before showing a camera outside the artwork', (
    tester,
  ) async {
    CameraShot? previewed;
    final fixture = await _pumpOverlay(
      tester,
      project: HandDrawProject(drawingImagePath: '/tmp/artwork.png'),
      onPreviewShot: (shot) => previewed = shot,
    );
    const outside = CameraView(centerX: 4, centerY: 4, viewportWidth: .25);
    fixture.editing.setEditorView(outside);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('camera-preview-current-view')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('camera-content-warning-dialog')),
      findsOneWidget,
    );
    expect(previewed, isNull);
    expect(_view(fixture.editor), outside);

    await tester.tap(
      find.byKey(const ValueKey('camera-content-warning-continue')),
    );
    await tester.pumpAndSettle();
    expect(previewed?.keyframes.single.view, outside);
  });

  testWidgets('saved view restoration is exact and does not touch history', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    const saved = CameraView(centerX: -.2, centerY: 1.3, viewportWidth: .27);
    final revision = fixture.editor.state.documentRevision;
    final history = fixture.editor.history.undoEntries.length;

    fixture.editing.restoreEditorView(saved);
    await tester.pump();

    expect(fixture.editing.state.editorView, saved);
    expect(fixture.editing.state.savedEditorView, saved);
    expect(fixture.editing.state.isEditorViewDirty, isFalse);
    expect(fixture.editor.state.documentRevision, revision);
    expect(fixture.editor.history.undoEntries, hasLength(history));
  });

  testWidgets(
    'canvas keeps composition commands while timing moves to shot properties',
    (tester) async {
      await _pumpOverlay(tester);
      for (final key in const [
        'camera-add-current-view',
        'camera-update-current-view',
        'camera-delete-current-view',
        'camera-preview-current-view',
        'camera-composition-grid',
        'camera-editable-output-frame',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      for (final movedKey in const [
        'camera-zoom-in-out-preset',
        'camera-movement-type',
        'camera-movement-duration',
        'camera-hold-duration',
      ]) {
        expect(find.byKey(ValueKey(movedKey)), findsNothing);
      }
      expect(find.textContaining('Advanced'), findsNothing);
      expect(find.textContaining('Start view'), findsNothing);
      expect(find.textContaining('End view'), findsNothing);
      for (final handle in const [
        'topLeft',
        'top',
        'topRight',
        'right',
        'bottomRight',
        'bottom',
        'bottomLeft',
        'left',
      ]) {
        expect(find.byKey(ValueKey('camera-resize-$handle')), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('camera-canvas-selected-frame')),
        findsNothing,
      );
    },
  );

  testWidgets('composition grid defaults to quarters and switches to thirds', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    final grid = find.byKey(const ValueKey('camera-composition-grid'));

    expect(
      tester.widget<DropdownButton<CameraCompositionGrid>>(grid).value,
      CameraCompositionGrid.quarters,
    );

    await tester.tap(grid);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3×3 · Rule of Thirds').last);
    await tester.pumpAndSettle();

    expect(
      fixture.editing.state.compositionGrid,
      CameraCompositionGrid.ruleOfThirds,
    );
    expect(
      tester.widget<DropdownButton<CameraCompositionGrid>>(grid).value,
      CameraCompositionGrid.ruleOfThirds,
    );

    fixture.editing.clear();
    expect(
      fixture.editing.state.compositionGrid,
      CameraCompositionGrid.ruleOfThirds,
    );
  });

  testWidgets('Zoom preset dialog creates three shots with three inputs', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    final original = fixture.editor.state.document.cameraTrack!.shots.single;

    final overlayContext = tester.element(find.byType(CameraCanvasOverlay));
    showCameraShotPropertiesDialog(
      context: overlayContext,
      editor: fixture.editor,
      editing: fixture.editing,
      shot: original,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('camera-shot-properties-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('camera-properties-zoom-preset')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('camera-zoom-preset-dialog')),
      findsOneWidget,
    );
    for (final key in const [
      'camera-zoom-preset-strength',
      'camera-zoom-preset-in-duration',
      'camera-zoom-preset-out-duration',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('camera-zoom-preset-apply')));
    await tester.pumpAndSettle();

    final shots = fixture.editor.state.document.cameraTrack!.shots;
    expect(shots, hasLength(3));
    expect(shots.first.startTime, original.startTime);
    expect(shots.last.endTime, original.endTime);
    expect(fixture.editing.state.primaryShotId, shots[1].id);
    fixture.editor.undoStroke();
    expect(fixture.editor.state.document.cameraTrack!.shots, [original]);
  });

  testWidgets('camera shot preview plays inside the open properties dialog', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    final original = fixture.editor.state.document.cameraTrack!.shots.single;
    final overlayContext = tester.element(find.byType(CameraCanvasOverlay));

    showCameraShotPropertiesDialog(
      context: overlayContext,
      editor: fixture.editor,
      editing: fixture.editing,
      shot: original,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview').last);
    await tester.pumpAndSettle();

    final progress = find.byKey(
      const ValueKey('camera-properties-preview-progress'),
    );
    expect(progress, findsOneWidget);
    expect(tester.widget<Slider>(progress).value, 0);
    final previewPainter = find.byKey(
      const ValueKey('camera-properties-resolved-preview-painter'),
    );
    expect(previewPainter, findsOneWidget);
    final initialPainter =
        tester.widget<CustomPaint>(previewPainter).painter
            as EditorCanvasPainter;
    expect(initialPainter.cameraOutputPreview, isTrue);
    expect(initialPainter.resolvedFrame?.time, original.startTime);

    await tester.tap(find.byKey(const ValueKey('camera-properties-preview')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('camera-shot-properties-dialog')),
      findsOneWidget,
    );
    expect(tester.widget<Slider>(progress).value, greaterThan(0));
    final advancedPainter =
        tester.widget<CustomPaint>(previewPainter).painter
            as EditorCanvasPainter;
    expect(
      advancedPainter.resolvedFrame!.time.microseconds,
      greaterThan(original.startTime.microseconds),
    );
    expect(advancedPainter.resolvedFrame!.drawing, isNotNull);

    await tester.tap(find.byKey(const ValueKey('camera-properties-preview')));
  });

  testWidgets('camera dialog endpoint stays inside the selected shot', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(tester);
    final first = fixture.editor.state.document.cameraTrack!.shots.single;
    fixture.editor.addCameraShotAtWithView(
      first.endTime,
      const CameraView(centerX: .8, centerY: .5, viewportWidth: .4),
    );
    final overlayContext = tester.element(find.byType(CameraCanvasOverlay));

    showCameraShotPropertiesDialog(
      context: overlayContext,
      editor: fixture.editor,
      editing: fixture.editing,
      shot: first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview').last);
    await tester.pumpAndSettle();
    final slider = find.byKey(
      const ValueKey('camera-properties-preview-progress'),
    );
    await tester.tapAt(tester.getTopRight(slider));
    await tester.pump();

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey(
                      'camera-properties-resolved-preview-painter',
                    ),
                  ),
                )
                .painter
            as EditorCanvasPainter;
    expect(
      painter.resolvedFrame!.time.microseconds,
      lessThan(first.endTime.microseconds),
    );
  });

  testWidgets('camera link tab uses the covered artwork block name', (
    tester,
  ) async {
    final fixture = await _pumpOverlay(
      tester,
      withShot: false,
      project: HandDrawProject(
        durationSeconds: 4,
        drawingDurationSeconds: 4,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        strokes: [
          DrawingStroke(
            id: 'first',
            name: 'Artwork 1',
            points: const [Offset(.1, .1), Offset(.4, .4)],
            sectionId: 'first-section',
          ),
          DrawingStroke(
            id: 'second',
            name: 'Artwork 2',
            points: const [Offset(.6, .6), Offset(.9, .9)],
            sectionId: 'second-section',
          ),
        ],
        timelineSectionOrder: const ['first-section', 'second-section'],
      ),
    );
    fixture.editor.addCameraShotAtWithView(
      TimelineTime.fromMicroseconds(2200000),
      const CameraView.identity(),
    );
    final shot = fixture.editor.state.document.cameraTrack!.shots.single;
    final overlayContext = tester.element(find.byType(CameraCanvasOverlay));

    showCameraShotPropertiesDialog(
      context: overlayContext,
      editor: fixture.editor,
      editing: fixture.editing,
      shot: shot,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link').last);
    await tester.pumpAndSettle();

    expect(find.text('Artwork 2'), findsOneWidget);
  });

  testWidgets('camera commands are docked outside the output viewport', (
    tester,
  ) async {
    final editor = EditorCubit();
    final editing = CameraEditingCubit();
    addTearDown(editor.close);
    addTearDown(editing.close);
    const saved = CameraView(centerX: .5, centerY: .5, viewportWidth: .6);
    editor.addCameraShotAtWithView(TimelineTime.zero, saved);
    final shot = editor.state.document.cameraTrack!.shots.single;
    editing.selectKeyframe(shot.id, shot.keyframes.single.id);
    editing.restoreEditorView(saved);
    const workspaceSize = Size(900, 600);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.fromSize(
            size: workspaceSize,
            child: EditorWorkspace(
              cubit: editor,
              layout: EditorLayoutSpec.fromConstraints(
                BoxConstraints.tight(workspaceSize),
              ),
              previewProgress: 0,
              isPreviewing: false,
              isPlaybackActive: false,
              interactionLocked: false,
              onSmartSectionSelected: () {},
              cameraEditing: editing,
              onPreviewCameraShot: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dock = tester.getRect(
      find.byKey(const ValueKey('camera-view-control-dock')),
    );
    final viewport = tester.getRect(find.byType(CanvasViewportFrame));

    expect(dock.bottom, lessThanOrEqualTo(viewport.top));
    expect(
      find.byKey(const ValueKey('canvas-player-controls')),
      findsOneWidget,
    );
  });

  testWidgets('unavailable camera commands stay visible and disabled', (
    tester,
  ) async {
    await _pumpOverlay(tester, withShot: false);

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('camera-add-current-view')),
          )
          .onPressed,
      isNotNull,
    );
    for (final key in const [
      'camera-update-current-view',
      'camera-delete-current-view',
    ]) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('camera-preview-current-view')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Delete and Preview operate on the selected single view', (
    tester,
  ) async {
    CameraShot? previewed;
    final fixture = await _pumpOverlay(
      tester,
      onPreviewShot: (shot) => previewed = shot,
    );
    final id = fixture.editor.state.document.cameraTrack!.shots.single.id;
    await tester.ensureVisible(
      find.byKey(const ValueKey('camera-preview-current-view')),
    );
    await tester.tap(find.byKey(const ValueKey('camera-preview-current-view')));
    expect(previewed?.id, id);

    await tester.ensureVisible(
      find.byKey(const ValueKey('camera-delete-current-view')),
    );
    await tester.tap(find.byKey(const ValueKey('camera-delete-current-view')));
    await tester.pump();
    expect(fixture.editor.state.document.cameraTrack!.shots, isEmpty);
    fixture.editor.undoStroke();
    expect(fixture.editor.state.document.cameraTrack!.shots.single.id, id);
  });

  testWidgets('Preview hides every camera editing overlay', (tester) async {
    final fixture = await _pumpOverlay(tester);
    fixture.editing.setCanvasMode(CameraCanvasMode.previewCamera);
    expect(fixture.editing.state.canvasMode, CameraCanvasMode.previewCamera);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('camera-fixed-output-viewport')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('camera-add-current-view')), findsNothing);
  });
}

Future<({EditorCubit editor, CameraEditingCubit editing})> _pumpOverlay(
  WidgetTester tester, {
  bool withShot = true,
  HandDrawProject? project,
  ValueChanged<CameraShot>? onPreviewShot,
}) async {
  final editor = project == null
      ? EditorCubit()
      : EditorCubit(initialState: testEditorState(project: project));
  final editing = CameraEditingCubit();
  addTearDown(editor.close);
  addTearDown(editing.close);
  if (withShot) {
    const saved = CameraView(centerX: .5, centerY: .5, viewportWidth: .6);
    editor.addCameraShotAtWithView(TimelineTime.zero, saved);
    final shot = editor.state.document.cameraTrack!.shots.single;
    editing.selectKeyframe(shot.id, shot.keyframes.single.id);
    editing.restoreEditorView(saved);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 500,
          child: BlocBuilder<EditorCubit, EditorState>(
            bloc: editor,
            builder: (context, _) => Column(
              children: [
                CameraViewControlBar(
                  editor: editor,
                  editing: editing,
                  readOnly: false,
                  playheadTime: TimelineTime.zero,
                  onPreviewShot: onPreviewShot ?? (_) {},
                ),
                Expanded(
                  child: CameraCanvasOverlay(
                    editor: editor,
                    editing: editing,
                    readOnly: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (editor: editor, editing: editing);
}

CameraView _view(EditorCubit editor) =>
    editor.state.document.cameraTrack!.shots.single.keyframes.single.view;
