import 'support/legacy_editor_state_fixture.dart';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvas enclosure creates an atomic scene used by Auto Path', () async {
    final image = await _image();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        drawingImage: image,
        smartSections: [
          _section('left', const ui.Rect.fromLTWH(0.1, 0.2, 0.2, 0.2)),
          _section('right', const ui.Rect.fromLTWH(0.7, 0.2, 0.2, 0.2)),
        ],
      ),
    );
    addTearDown(cubit.close);
    addTearDown(image.dispose);
    const artworkRect = ui.Rect.fromLTWH(0, 0, 100, 100);

    cubit.setTool(EditorTool.sceneGroup);
    cubit.beginStroke(const ui.Offset(5, 15), artworkRect);
    cubit.updateStroke(const ui.Offset(38, 15), artworkRect);
    cubit.updateStroke(const ui.Offset(38, 48), artworkRect);
    cubit.updateStroke(const ui.Offset(5, 48), artworkRect);
    cubit.endStroke();

    expect(cubit.timelineSceneGroups, hasLength(1));
    expect(cubit.timelineSceneGroups.single.sectionIds, ['left']);
    expect(cubit.tool, EditorTool.select);

    await cubit.applySmartPathSuggestions();

    expect(cubit.project.strokes, hasLength(2));
    expect(cubit.project.strokes.first.name, 'left');
    expect(
      cubit.project.strokes.first.sceneGroupId,
      cubit.project.sceneGroups.single.id,
    );
    expect(cubit.project.strokes.last.name, 'right');
  });

  test(
    'timeline selection groups items and drag order reaches generated strokes',
    () async {
      final image = await _image();
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            timelineSectionOrder: const ['left', 'middle', 'right'],
          ),
          drawingImage: image,
          smartSections: [
            _section('left', const ui.Rect.fromLTWH(0.1, 0.2, 0.15, 0.2)),
            _section('middle', const ui.Rect.fromLTWH(0.4, 0.2, 0.15, 0.2)),
            _section('right', const ui.Rect.fromLTWH(0.7, 0.2, 0.15, 0.2)),
          ],
        ),
      );
      addTearDown(cubit.close);
      addTearDown(image.dispose);

      cubit.toggleTimelineSectionSelection('left');
      cubit.toggleTimelineSectionSelection('right');
      cubit.createTimelineGroupFromSelection();

      expect(cubit.timelineSceneGroups.single.sectionIds, ['left', 'right']);
      expect(cubit.timelineSectionOrder, ['left', 'right', 'middle']);

      cubit.reorderTimelineNode(
        'section:middle',
        'scene:${cubit.timelineSceneGroups.single.id}',
      );
      expect(cubit.timelineSectionOrder, ['middle', 'left', 'right']);

      await cubit.applySmartPathSuggestions();
      expect(cubit.project.strokes.map((stroke) => stroke.sectionId).toList(), [
        'middle',
        'left',
        'right',
      ]);
    },
  );

  test('applied section clips reorder complete stroke blocks', () {
    DrawingStroke stroke(String id, String section, double x) => DrawingStroke(
      id: id,
      name: id,
      sectionId: section,
      points: [ui.Offset(x, 0.2), ui.Offset(x + 0.05, 0.25)],
    );
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            stroke('a-1', 'a', 0.1),
            stroke('a-2', 'a', 0.2),
            stroke('b-1', 'b', 0.6),
          ],
          timelineSectionOrder: const ['a', 'b'],
        ),
      ),
    );
    addTearDown(cubit.close);

    cubit.reorderTimelineNode('section:b', 'section:a');

    expect(cubit.timelineSectionOrder, ['b', 'a']);
    expect(cubit.project.strokes.map((stroke) => stroke.id), [
      'b-1',
      'a-1',
      'a-2',
    ]);
  });
}

SmartPathSection _section(String id, ui.Rect bounds) => SmartPathSection(
  id: id,
  kind: SmartSectionKind.shape,
  bounds: bounds,
  label: id,
  paths: [
    SmartGeneratedPath(points: [bounds.topLeft, bounds.bottomRight]),
  ],
  recommendedRevealWidth: 0.01,
  mode: SmartSectionMode.handDraw,
);

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 100, 100),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}
