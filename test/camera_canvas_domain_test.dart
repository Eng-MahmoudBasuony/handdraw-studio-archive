import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/camera_world_bounds.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/quick_camera_fit_service.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_transform.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  test('canvas transform round trips normalized world coordinates', () {
    const transform = CameraCanvasTransform(Rect.fromLTWH(20, 10, 800, 400), 2);
    final canvas = transform.worldToCanvas(.25, .75);
    expect(transform.canvasToWorld(canvas), const Offset(.25, .75));
    expect(
      transform.frameFor(const CameraView.identity()),
      const Rect.fromLTWH(20, 10, 800, 400),
    );
  });

  for (final fixture in const [
    (zoom: .5, pan: Offset(-120, 40)),
    (zoom: 2.0, pan: Offset(160, -75)),
  ]) {
    test('editor viewport ${fixture.zoom}x remains an isolated adapter', () {
      final transform = CameraCanvasTransform(
        const Rect.fromLTWH(20, 10, 800, 400),
        2,
        editorZoom: fixture.zoom,
        editorPan: fixture.pan,
      );
      const world = Offset(-.2, 1.3);
      final canvas = transform.worldToCanvas(world.dx, world.dy);
      expect(transform.canvasToWorld(canvas).dx, closeTo(world.dx, 1e-9));
      expect(transform.canvasToWorld(canvas).dy, closeTo(world.dy, 1e-9));
      const camera = CameraView(centerX: .4, centerY: .6, viewportWidth: .5);
      transform.frameFor(camera);
      expect(
        camera,
        const CameraView(centerX: .4, centerY: .6, viewportWidth: .5),
      );
    });
  }

  test('corner resize anchors opposite corner unless Alt centers it', () {
    const transform = CameraCanvasTransform(Rect.fromLTWH(0, 0, 800, 400), 2);
    const source = CameraView(centerX: .5, centerY: .5, viewportWidth: .4);
    final anchored = transform.resizeFromCorner(source, const Offset(80, 40));
    final centered = transform.resizeFromCorner(
      source,
      const Offset(80, 40),
      centered: true,
    );
    expect(anchored.centerX, .55);
    expect(anchored.centerY, .55);
    expect(centered.centerX, source.centerX);
    expect(centered.centerY, source.centerY);
    expect(centered.viewportWidth, anchored.viewportWidth);
  });

  test('quick fit preserves output aspect and central padding policy', () {
    final result = const QuickCameraFitService().fit(
      bounds: const CameraWorldBounds(left: .2, top: .3, right: .6, bottom: .5),
      projectAspectRatio: 2,
    );
    expect(result.isSuccess, isTrue);
    expect(result.view!.centerX, closeTo(.4, 1e-9));
    expect(result.view!.centerY, closeTo(.4, 1e-9));
    expect(result.view!.viewportWidth, closeTo(.496, 1e-9));
    expect(
      result.view!.normalizedViewportHeightFor(
        projectAspectRatio: 2,
        outputAspectRatio: 2,
      ),
      closeTo(.496, 1e-9),
    );
  });

  test('quick fit returns typed failures for invalid inputs', () {
    const service = QuickCameraFitService();
    expect(
      service.fit(bounds: null, projectAspectRatio: 1).failure,
      CameraFitFailure.emptyBounds,
    );
    expect(
      service
          .fit(
            bounds: const CameraWorldBounds(
              left: 0,
              top: 0,
              right: 1,
              bottom: 1,
            ),
            projectAspectRatio: 0,
          )
          .failure,
      CameraFitFailure.invalidAspectRatio,
    );
  });

  test('create from canvas is atomic when camera view validation fails', () {
    final editor = EditorCubit();
    addTearDown(editor.close);
    final revision = editor.state.documentRevision;
    final history = editor.history.undoEntries.length;
    final created = editor.addCameraShotAtWithView(
      TimelineTime.zero,
      const CameraView(
        centerX: double.infinity,
        centerY: .5,
        viewportWidth: .5,
      ),
    );
    expect(created, isFalse);
    expect(editor.state.document.cameraTrack, isNull);
    expect(editor.state.documentRevision, revision);
    expect(editor.history.undoEntries.length, history);
  });

  test('shot suggestion fits the active section away from origin', () {
    final editor = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          durationSeconds: 2,
          drawingDurationSeconds: 2,
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          timelineSectionOrder: const ['far-section'],
          strokes: [
            DrawingStroke(
              id: 'hidden-origin-stroke',
              name: 'Hidden origin element',
              sectionId: 'far-section',
              hidden: true,
              points: const [Offset.zero, Offset(.1, .1)],
            ),
            DrawingStroke(
              id: 'far-stroke',
              name: 'Far element',
              sectionId: 'far-section',
              // Reveal guides can legitimately differ from the visible SVG
              // pixels; camera fitting must use the visual clip bounds.
              points: const [Offset(.1, .1), Offset(.2, .2)],
              clipBounds: const Rect.fromLTRB(.72, .68, .92, .82),
            ),
          ],
        ),
      ),
    );
    addTearDown(editor.close);

    final revision = editor.state.documentRevision;
    final history = editor.history.undoEntries.length;
    final view = editor.suggestedCameraViewAt(TimelineTime.zero);

    expect(view.centerX, closeTo(.82, .001));
    expect(view.centerY, closeTo(.75, .001));
    expect(view.viewportWidth, lessThan(.5));
    expect(editor.state.documentRevision, revision);
    expect(editor.history.undoEntries.length, history);
  });

  for (final bounds in const [
    CameraWorldBounds(left: .4, top: .1, right: .6, bottom: .9),
    CameraWorldBounds(left: -.3, top: .3, right: 1.4, bottom: .5),
  ]) {
    test(
      'quick fit handles tall, wide, padded, and outside-artwork bounds',
      () {
        final result = const QuickCameraFitService().fit(
          bounds: bounds,
          projectAspectRatio: 16 / 9,
        );
        expect(result.isSuccess, isTrue);
        expect(result.view!.viewportWidth, greaterThan(bounds.width));
        expect(
          result.view!.normalizedViewportHeightFor(
            projectAspectRatio: 16 / 9,
            outputAspectRatio: 16 / 9,
          ),
          greaterThanOrEqualTo(bounds.height),
        );
      },
    );
  }
}
