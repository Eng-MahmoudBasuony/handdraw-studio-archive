import 'support/legacy_editor_state_fixture.dart';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

void main() {
  const editor = PathNodeEditor();

  test('moves a quadratic control point immutably', () {
    final geometry = StrokePathGeometry(
      start: const Offset(0.1, 0.8),
      segments: const [
        StrokeQuadraticSegment(
          control: Offset(0.5, 0.1),
          end: Offset(0.9, 0.8),
        ),
      ],
    );

    final edited = editor.move(
      geometry,
      const PathNodeReference(
        kind: PathNodeKind.quadraticControl,
        segmentIndex: 0,
      ),
      const Offset(0.5, 0.25),
    );

    expect(
      (edited.segments.single as StrokeQuadraticSegment).control,
      const Offset(0.5, 0.25),
    );
    expect(
      (geometry.segments.single as StrokeQuadraticSegment).control,
      const Offset(0.5, 0.1),
    );
  });

  test('moving an anchor preserves adjacent cubic handle offsets', () {
    final source = StrokePathGeometry(
      start: const Offset(0.1, 0.2),
      segments: const [
        StrokeCubicSegment(
          control1: Offset(0.2, 0.1),
          control2: Offset(0.4, 0.5),
          end: Offset(0.5, 0.5),
        ),
        StrokeCubicSegment(
          control1: Offset(0.6, 0.5),
          control2: Offset(0.8, 0.9),
          end: Offset(0.9, 0.8),
        ),
      ],
    );

    final moved = editor.move(
      source,
      const PathNodeReference(kind: PathNodeKind.endAnchor, segmentIndex: 0),
      const Offset(0.55, 0.6),
    );
    final incoming = moved.segments.first as StrokeCubicSegment;
    final outgoing = moved.segments.last as StrokeCubicSegment;

    expect(incoming.end, const Offset(0.55, 0.6));
    expect(incoming.control2.dx, closeTo(0.45, 0.000001));
    expect(incoming.control2.dy, closeTo(0.6, 0.000001));
    expect(outgoing.control1.dx, closeTo(0.65, 0.000001));
    expect(outgoing.control1.dy, closeTo(0.6, 0.000001));
    expect(source.segments.first.end, const Offset(0.5, 0.5));
  });

  test('moving a smooth handle keeps the opposite handle tangent', () {
    final source = StrokePathGeometry(
      start: const Offset(0, 0.5),
      segments: const [
        StrokeCubicSegment(
          control1: Offset(0.1, 0.5),
          control2: Offset(0.4, 0.5),
          end: Offset(0.5, 0.5),
        ),
        StrokeCubicSegment(
          control1: Offset(0.6, 0.5),
          control2: Offset(0.9, 0.5),
          end: Offset(1, 0.5),
        ),
      ],
      smoothAnchors: const [1],
    );

    final moved = editor.move(
      source,
      const PathNodeReference(kind: PathNodeKind.control1, segmentIndex: 1),
      const Offset(0.6, 0.7),
    );
    final incoming = moved.segments.first as StrokeCubicSegment;
    final outgoing = moved.segments.last as StrokeCubicSegment;
    final anchor = incoming.end;
    final a = anchor - incoming.control2;
    final b = outgoing.control1 - anchor;

    expect(a.dx * b.dy - a.dy * b.dx, closeTo(0, 0.000001));
    expect(a.dx * b.dx + a.dy * b.dy, greaterThan(0));
  });

  test(
    'split, delete, smooth, join, and start-node operations stay editable',
    () {
      final curve = StrokePathGeometry(
        start: const Offset(0, 0),
        segments: const [
          StrokeCubicSegment(
            control1: Offset(0.2, 0),
            control2: Offset(0.3, 0.5),
            end: Offset(0.5, 0.5),
          ),
          StrokeCubicSegment(
            control1: Offset(0.7, 0.5),
            control2: Offset(0.8, 1),
            end: Offset(1, 1),
          ),
        ],
      );

      final subdivided = editor.splitSegment(curve, 0);
      expect(subdivided.segments, hasLength(3));
      expect(subdivided.end, curve.end);
      expect(subdivided.smoothAnchors, contains(1));

      final smooth = editor.setAnchorSmooth(
        curve,
        const PathNodeReference(kind: PathNodeKind.endAnchor, segmentIndex: 0),
        smooth: true,
      );
      expect(smooth.smoothAnchors, contains(1));
      final incoming = smooth.segments.first as StrokeCubicSegment;
      final outgoing = smooth.segments.last as StrokeCubicSegment;
      final incomingDirection = incoming.end - incoming.control2;
      final outgoingDirection = outgoing.control1 - incoming.end;
      expect(
        incomingDirection.dx * outgoingDirection.dy -
            incomingDirection.dy * outgoingDirection.dx,
        closeTo(0, 0.000001),
      );

      final split = editor.splitPath(curve, 1);
      expect(split, hasLength(2));
      expect(editor.joinPaths(split.first, split.last).end, curve.end);

      final deleted = editor.deleteAnchor(
        subdivided,
        const PathNodeReference(kind: PathNodeKind.endAnchor, segmentIndex: 0),
      );
      expect(deleted.segments, hasLength(2));

      final closed = StrokePathGeometry(
        start: const Offset(0, 0),
        segments: const [
          StrokeLineSegment(end: Offset(1, 0)),
          StrokeLineSegment(end: Offset(1, 1)),
          StrokeLineSegment(end: Offset(0, 1)),
        ],
        closed: true,
      );
      final restarted = editor.setStartAnchor(closed, 2);
      expect(restarted.start, const Offset(1, 1));
      expect(restarted.closed, isTrue);
    },
  );

  test('enumerating and moving one node remains fast with 1000 nodes', () {
    final geometry = StrokePathGeometry(
      start: Offset.zero,
      segments: [
        for (var index = 1; index <= 1000; index++)
          StrokeLineSegment(end: Offset(index / 1000, 0.5)),
      ],
    );
    final stopwatch = Stopwatch()..start();
    final nodes = editor.nodes(geometry);
    final edited = editor.move(
      geometry,
      const PathNodeReference(kind: PathNodeKind.endAnchor, segmentIndex: 499),
      const Offset(0.5, 0.55),
    );
    stopwatch.stop();

    expect(nodes, hasLength(1001));
    expect(edited.segments[499].end.dy, 0.55);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });

  test('one node drag creates one atomic undo entry', () {
    final geometry = StrokePathGeometry(
      start: const Offset(0.1, 0.2),
      segments: const [
        StrokeCubicSegment(
          control1: Offset(0.2, 0.1),
          control2: Offset(0.7, 0.8),
          end: Offset(0.9, 0.7),
        ),
      ],
    );
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(id: 'vector', name: 'Vector', geometry: geometry),
          ],
        ),
        tool: EditorTool.select,
        selectedStrokeIndex: 0,
      ),
    );
    addTearDown(cubit.close);
    const artworkRect = Rect.fromLTWH(0, 0, 100, 100);

    expect(cubit.beginPathNodeEdit(const Offset(10, 20), artworkRect), isTrue);
    cubit.updatePathNodeEdit(const Offset(15, 25), artworkRect);
    cubit.updatePathNodeEdit(const Offset(20, 30), artworkRect);
    cubit.endPathNodeEdit();

    expect(
      cubit.project.strokes.single.geometry!.start,
      const Offset(0.2, 0.3),
    );
    cubit.undoStroke();
    expect(cubit.project.strokes.single.geometry!.start, geometry.start);
    cubit.redoStroke();
    expect(
      cubit.project.strokes.single.geometry!.start,
      const Offset(0.2, 0.3),
    );
  });

  test('snap is optional and cancel restores the pointer-down snapshot', () {
    final geometry = StrokePathGeometry(
      start: const Offset(0.1, 0.2),
      segments: const [StrokeLineSegment(end: Offset(0.9, 0.7))],
    );
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(id: 'vector', name: 'Vector', geometry: geometry),
          ],
        ),
        tool: EditorTool.select,
        selectedStrokeIndex: 0,
        nodeSnapEnabled: true,
      ),
    );
    addTearDown(cubit.close);
    const artworkRect = Rect.fromLTWH(0, 0, 100, 100);

    cubit.beginPathNodeEdit(const Offset(10, 20), artworkRect);
    cubit.updatePathNodeEdit(const Offset(13.3, 26.7), artworkRect);
    expect(
      cubit.project.strokes.single.geometry!.start,
      const Offset(0.135, 0.265),
    );
    cubit.cancelPathNodeEdit();

    expect(cubit.project.strokes.single.geometry!.start, geometry.start);
    cubit.beginPathNodeEdit(const Offset(10, 20), artworkRect);
    cubit.updatePathNodeEdit(const Offset(20, 30), artworkRect);
    cubit.endPathNodeEdit();
    cubit.undoStroke();
    expect(cubit.project.strokes.single.geometry!.start, geometry.start);
  });

  test('shift-style additive selection moves multiple normalized nodes', () {
    final geometry = StrokePathGeometry(
      start: const Offset(0.1, 0.2),
      segments: const [StrokeLineSegment(end: Offset(0.8, 0.7))],
    );
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(id: 'vector', name: 'Vector', geometry: geometry),
          ],
        ),
        tool: EditorTool.select,
        selectedStrokeIndex: 0,
      ),
    );
    addTearDown(cubit.close);
    const artworkRect = Rect.fromLTWH(20, 30, 200, 100);

    cubit.beginPathNodeEdit(const Offset(40, 50), artworkRect);
    cubit.endPathNodeEdit();
    cubit.beginPathNodeEdit(
      const Offset(180, 100),
      artworkRect,
      additiveSelection: true,
    );
    cubit.updatePathNodeEdit(const Offset(190, 105), artworkRect);
    cubit.endPathNodeEdit();

    final edited = cubit.project.strokes.single.geometry!;
    expect(edited.start.dx, closeTo(0.15, 0.000001));
    expect(edited.start.dy, closeTo(0.25, 0.000001));
    expect(edited.end.dx, closeTo(0.85, 0.000001));
    expect(edited.end.dy, closeTo(0.75, 0.000001));
  });

  test('canvas hit testing selects the nearest visible SVG path', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'top',
              name: 'Top',
              points: const [Offset(0.1, 0.2), Offset(0.9, 0.2)],
            ),
            DrawingStroke(
              id: 'bottom',
              name: 'Bottom',
              points: const [Offset(0.1, 0.8), Offset(0.9, 0.8)],
            ),
          ],
        ),
        tool: EditorTool.select,
      ),
    );
    addTearDown(cubit.close);
    const artworkRect = Rect.fromLTWH(0, 0, 200, 100);

    expect(cubit.selectStrokeAt(const Offset(100, 79), artworkRect), isTrue);
    expect(cubit.selectedStrokeIndex, 1);
    cubit.hoverStrokeAt(const Offset(100, 21), artworkRect);
    expect(cubit.state.hoveredStrokeIndex, 0);
    cubit.hoverStrokeAt(null, artworkRect);
    expect(cubit.state.hoveredStrokeIndex, isNull);
  });
}
