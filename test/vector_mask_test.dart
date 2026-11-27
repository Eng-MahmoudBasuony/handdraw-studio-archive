import 'support/legacy_editor_state_fixture.dart';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';

void main() {
  test('vector masks round-trip with editable geometry', () {
    final project = HandDrawProject(
      strokes: [
        DrawingStroke(
          id: 'masked',
          name: 'Masked',
          geometry: StrokePathGeometry(
            start: const ui.Offset(0.1, 0.5),
            segments: const [StrokeLineSegment(end: ui.Offset(0.9, 0.5))],
          ),
          vectorMaskStrokes: [
            VectorMaskStroke(
              geometry: StrokePathGeometry(
                start: const ui.Offset(0.5, 0.2),
                segments: const [StrokeLineSegment(end: ui.Offset(0.5, 0.8))],
              ),
              widthFraction: 0.12,
              featherFraction: 0.025,
              clipToLayer: false,
              operation: VectorMaskOperation.erase,
            ),
          ],
        ),
      ],
    );

    final restored = HandDrawProject.fromJson(project.toJson());
    final mask = restored.strokes.single.vectorMaskStrokes.single;
    expect(mask.operation, VectorMaskOperation.erase);
    expect(mask.widthFraction, 0.12);
    expect(mask.featherFraction, 0.025);
    expect(mask.clipToLayer, isFalse);
    expect(mask.geometry.start, const ui.Offset(0.5, 0.2));
    expect(mask.geometry.segments.single.end, const ui.Offset(0.5, 0.8));
  });

  test('mask editor adds an immutable erase stroke with atomic undo', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final drawing = await picture.toImage(100, 100);
    picture.dispose();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 100,
          canvasHeight: 100,
          strokes: [
            DrawingStroke(
              id: 'base',
              name: 'Base',
              points: const [ui.Offset(0.1, 0.5), ui.Offset(0.9, 0.5)],
            ),
          ],
        ),
        tool: EditorTool.maskErase,
        selectedStrokeIndex: 0,
        drawingImage: drawing,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      drawing.dispose();
    });
    const artworkRect = ui.Rect.fromLTWH(0, 0, 100, 100);

    cubit.beginStroke(const ui.Offset(50, 35), artworkRect);
    cubit.updateStroke(const ui.Offset(50, 65), artworkRect);
    cubit.endStroke();

    final mask = cubit.project.strokes.single.vectorMaskStrokes.single;
    expect(mask.operation, VectorMaskOperation.erase);
    expect(mask.widthFraction, closeTo(0.54, 0.0001));
    cubit.undoStroke();
    expect(cubit.project.strokes.single.vectorMaskStrokes, isEmpty);
    cubit.redoStroke();
    expect(cubit.project.strokes.single.vectorMaskStrokes, hasLength(1));
  });

  test(
    'shared compositor applies an erase mask to transparent output',
    () async {
      final sourceRecorder = ui.PictureRecorder();
      ui.Canvas(sourceRecorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const ui.Color(0xFF224466),
      );
      final sourcePicture = sourceRecorder.endRecording();
      final source = await sourcePicture.toImage(100, 100);
      sourcePicture.dispose();

      final revealPath = ui.Path()
        ..moveTo(10, 50)
        ..lineTo(90, 50);
      final eraseGeometry = StrokePathGeometry(
        start: const ui.Offset(0.5, 0.2),
        segments: const [StrokeLineSegment(end: ui.Offset(0.5, 0.8))],
      );
      final snapshot = TimelineSnapshot(
        revealedPaths: [
          RevealedPath(
            path: revealPath,
            sectionIndex: 0,
            revealWidth: 30,
            vectorMaskStrokes: [
              VectorMaskStroke(
                geometry: eraseGeometry,
                widthFraction: 0.20,
                operation: VectorMaskOperation.erase,
              ),
            ],
          ),
        ],
        handPosition: ui.Offset.zero,
        handAngle: 0,
        handVisible: false,
      );
      final outputRecorder = ui.PictureRecorder();
      drawRevealedArtwork(
        canvas: ui.Canvas(outputRecorder),
        image: source,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        snapshot: snapshot,
        defaultRevealWidth: 30,
      );
      final outputPicture = outputRecorder.endRecording();
      final output = await outputPicture.toImage(100, 100);
      outputPicture.dispose();
      final rgba = (await output.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      int alphaAt(int x, int y) => rgba[(y * 100 + x) * 4 + 3];

      expect(alphaAt(25, 50), 255);
      expect(alphaAt(50, 50), 0);
      expect(alphaAt(75, 50), 255);
      output.dispose();
      source.dispose();
    },
  );

  test(
    'filled SVG keeps its card solid while deferring label pixels',
    () async {
      final sourceRecorder = ui.PictureRecorder();
      final sourceCanvas = ui.Canvas(sourceRecorder);
      sourceCanvas.drawRect(
        const ui.Rect.fromLTWH(10, 20, 80, 50),
        ui.Paint()..color = const ui.Color(0xFF2F6FED),
      );
      sourceCanvas.drawRect(
        const ui.Rect.fromLTWH(30, 35, 40, 20),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      final sourcePicture = sourceRecorder.endRecording();
      final source = await sourcePicture.toImage(100, 100);
      sourcePicture.dispose();
      final revealPath = ui.Path()
        ..moveTo(10, 45)
        ..lineTo(50, 45);
      final snapshot = TimelineSnapshot(
        revealedPaths: [
          RevealedPath(
            path: revealPath,
            sectionIndex: 0,
            revealWidth: 54,
            clipRect: const ui.Rect.fromLTWH(10, 20, 80, 50),
            exclusionRects: const [ui.Rect.fromLTWH(30, 35, 40, 20)],
            revealStyle: RevealMaskStyle.directionalWipe,
            fillColorValue: 0xFF2F6FED,
          ),
        ],
        handPosition: ui.Offset.zero,
        handAngle: 0,
        handVisible: false,
      );
      final outputRecorder = ui.PictureRecorder();
      drawRevealedArtwork(
        canvas: ui.Canvas(outputRecorder),
        image: source,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        snapshot: snapshot,
        defaultRevealWidth: 20,
      );
      final outputPicture = outputRecorder.endRecording();
      final output = await outputPicture.toImage(100, 100);
      outputPicture.dispose();
      final rgba = (await output.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      List<int> pixel(int x, int y) =>
          rgba.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);

      expect(pixel(35, 45), [0x2F, 0x6F, 0xED, 0xFF]);
      expect(pixel(75, 45)[3], 0);
      output.dispose();
      source.dispose();
    },
  );
}
