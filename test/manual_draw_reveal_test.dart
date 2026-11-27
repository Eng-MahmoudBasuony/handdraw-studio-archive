import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/domain/manual_reveal_policy.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  test(
    'manual draw and reveal stores editable ordered paths with authored widths',
    () async {
      final image = await _solidImage();
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 100,
            canvasHeight: 100,
            drawingImagePath: '/tmp/manual-reveal.png',
            durationSeconds: 4,
            drawingDurationSeconds: 4,
            startDelaySeconds: 0,
            endHoldSeconds: 0,
            revealWidth: 32,
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      cubit.setTool(EditorTool.drawPath);
      _draw(cubit, const [
        ui.Offset(10, 20),
        ui.Offset(45, 35),
        ui.Offset(90, 20),
      ]);
      cubit.setRevealWidth(60);
      _draw(cubit, const [ui.Offset(10, 70), ui.Offset(90, 70)]);

      expect(cubit.state.document.strokes, hasLength(2));
      final first = cubit.state.document.strokes.first;
      final second = cubit.state.document.strokes.last;
      expect(first.revealOnly, isFalse);
      expect(first.revealStyle, DocumentRevealStyle.brush);
      expect(first.revealWidth, 32);
      expect(second.revealWidth, 60);
      expect(first.geometry, isNotNull);
      expect(first.geometry!.start, const ui.Offset(0.1, 0.2));
      expect(first.geometry!.end, const ui.Offset(0.9, 0.2));
      expect(first.assetId, cubit.state.document.artworkAssetId);
      expect(
        cubit.project.strokes.map((stroke) => stroke.id),
        orderedEquals([first.id.value, second.id.value]),
      );

      final snapshot = buildTimelineSnapshot(
        strokes: cubit.project.strokes,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        timingRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        progress: 0.2,
        durationSeconds: cubit.project.durationSeconds,
        drawingDurationSeconds: cubit.project.drawingDurationSeconds,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      expect(snapshot.phase, TimelinePhase.drawing);
      expect(snapshot.handVisible, isTrue);
      expect(snapshot.penIsDrawing, isTrue);
      expect(snapshot.cursor?.strokeId, first.id.value);
      expect(snapshot.revealedPaths.last.revealWidth, 32);

      cubit.undoStroke();
      expect(cubit.state.document.strokes, hasLength(1));
      cubit.redoStroke();
      expect(cubit.state.document.strokes, hasLength(2));
    },
  );

  test(
    'manual path is inserted into the selected scene in authored order',
    () async {
      final image = await _solidImage();
      final project = HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        drawingImagePath: '/tmp/manual-scene.png',
        strokes: [
          DrawingStroke(
            id: 'scene-a-existing',
            name: 'Scene A',
            sectionId: 'section-a',
            points: const [ui.Offset(0.1, 0.2), ui.Offset(0.9, 0.2)],
          ),
          DrawingStroke(
            id: 'scene-b-existing',
            name: 'Scene B',
            sectionId: 'section-b',
            points: const [ui.Offset(0.1, 0.8), ui.Offset(0.9, 0.8)],
          ),
        ],
        timelineSectionOrder: const ['section-a', 'section-b'],
        sceneGroups: [
          DrawingSceneGroup(
            id: 'scene-a',
            name: 'Scene A',
            sectionIds: ['section-a'],
          ),
          DrawingSceneGroup(
            id: 'scene-b',
            name: 'Scene B',
            sectionIds: ['section-b'],
          ),
        ],
      );
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: project,
          drawingImage: image,
          selectedTimelineSceneId: 'scene-a',
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      cubit.setTool(EditorTool.drawPath);
      _draw(cubit, const [ui.Offset(10, 40), ui.Offset(90, 40)]);

      expect(
        cubit.state.document.strokes.map((stroke) => stroke.id.value),
        orderedEquals([
          'scene-a-existing',
          cubit.state.document.strokes[1].id.value,
          'scene-b-existing',
        ]),
      );
      expect(cubit.state.document.strokes[1].sectionId, SectionId('section-a'));
      expect(cubit.state.selectedStrokeIndex, 1);
    },
  );

  test(
    'manual brush starts broad and keeps an explicit authored override',
    () async {
      final image = await _solidImage();
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 1000,
            canvasHeight: 1000,
            drawingImagePath: '/tmp/manual-broad-reveal.png',
            revealWidth: 32,
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      cubit.setTool(EditorTool.drawPath);
      expect(cubit.manualRevealWidth, 220);
      _draw(cubit, const [ui.Offset(10, 30), ui.Offset(90, 30)]);
      expect(cubit.state.document.strokes.single.revealWidth, 220);
      expect(cubit.project.revealWidth, 32);

      cubit.setManualRevealWidth(180);
      expect(cubit.state.document.strokes.first.revealWidth, 180);
      _draw(cubit, const [ui.Offset(10, 70), ui.Offset(90, 70)]);
      expect(cubit.state.document.strokes.last.revealWidth, 180);
      expect(cubit.project.revealWidth, 32);
    },
  );

  test('Reveal Text uses the same broad authored brush control', () async {
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 1000,
          canvasHeight: 1000,
          drawingImagePath: '/tmp/manual-text-reveal.png',
          revealWidth: 32,
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
    });

    cubit.setTool(EditorTool.revealText);
    cubit.setManualRevealWidth(300);
    _draw(cubit, const [ui.Offset(10, 50), ui.Offset(90, 50)]);

    final stroke = cubit.state.document.strokes.single;
    expect(stroke.revealOnly, isTrue);
    expect(stroke.revealWidth, 300);

    cubit.setManualRevealWidth(360);
    expect(cubit.state.document.strokes.single.revealWidth, 360);
  });

  test('manual reveal brush reaches its 960px production ceiling', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);

    cubit.setManualRevealWidth(2000);

    expect(cubit.manualRevealWidth, ManualRevealPolicy.maximumWidth);
    expect(cubit.manualRevealWidth, 960);
  });
}

void _draw(EditorCubit cubit, List<ui.Offset> points) {
  const rect = ui.Rect.fromLTWH(0, 0, 100, 100);
  cubit.beginStroke(points.first, rect);
  for (final point in points.skip(1)) {
    cubit.updateStroke(point, rect);
  }
  cubit.endStroke();
}

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 100, 100),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}
