import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_visual_compositor.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('identity camera is pixel-identical to legacy renderer', () async {
    final source = await _source();
    final project = _project();
    final legacy = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 1,
    );
    final resolved = await _render(
      source,
      const ResolvedSingleCameraView(CameraView.identity()),
    );
    expect(await _rgba(resolved), await _rgba(legacy));
    legacy.dispose();
    resolved.dispose();
    source.dispose();
  });
  test('zoom and pan select world regions without clamping', () async {
    final source = await _source();
    final left = await _render(
      source,
      const ResolvedSingleCameraView(
        CameraView(centerX: .25, centerY: .5, viewportWidth: .5),
      ),
    );
    final right = await _render(
      source,
      const ResolvedSingleCameraView(
        CameraView(centerX: .75, centerY: .5, viewportWidth: .5),
      ),
    );
    expect((await _pixel(left, 50, 50)).r, greaterThan(240));
    expect((await _pixel(right, 50, 50)).b, greaterThan(240));
    left.dispose();
    right.dispose();
    source.dispose();
  });
  test(
    'camera bounds are the literal video crop in preview and export',
    () async {
      final source = await _quadrantSource();
      const camera = ResolvedSingleCameraView(
        CameraView(centerX: .25, centerY: .25, viewportWidth: .5),
      );
      final preview = await _renderPreview(source, camera);
      final exported = await _render(source, camera);

      expect(await _rgba(preview), await _rgba(exported));
      for (final point in const [
        (10, 10),
        (90, 10),
        (50, 50),
        (10, 90),
        (90, 90),
      ]) {
        expect(
          await _pixel(preview, point.$1, point.$2),
          const _Pixel(255, 0, 0, 255),
          reason: 'Only the red top-left camera region should fill the output.',
        );
      }

      preview.dispose();
      exported.dispose();
      source.dispose();
    },
  );
  test(
    'fade is premultiplied cross-dissolve and endpoints match singles',
    () async {
      final source = await _source();
      const from = CameraView(centerX: .25, centerY: .5, viewportWidth: .5);
      const to = CameraView(centerX: .75, centerY: .5, viewportWidth: .5);
      final a = await _render(source, const ResolvedSingleCameraView(from));
      final b = await _render(source, const ResolvedSingleCameraView(to));
      final zero = await _render(
        source,
        const ResolvedCameraBlend(fromView: from, toView: to, targetOpacity: 0),
      );
      final half = await _render(
        source,
        const ResolvedCameraBlend(
          fromView: from,
          toView: to,
          targetOpacity: .5,
        ),
      );
      final one = await _render(
        source,
        const ResolvedCameraBlend(fromView: from, toView: to, targetOpacity: 1),
      );
      expect(await _rgba(zero), await _rgba(a));
      expect(await _rgba(one), await _rgba(b));
      final color = await _pixel(half, 50, 50);
      expect(color.r, closeTo(127, 2));
      expect(color.b, closeTo(127, 2));
      expect(color.a, closeTo(255, 1));
      for (final image in [a, b, zero, half, one]) {
        image.dispose();
      }
      source.dispose();
    },
  );
  test('outside-artwork is true alpha or project background', () async {
    final source = await _source();
    const outside = ResolvedSingleCameraView(
      CameraView(centerX: 4, centerY: 4, viewportWidth: .25),
    );
    final transparent = await _render(source, outside);
    final opaque = await _render(
      source,
      outside,
      target: const RenderTarget.opaque(ui.Color(0xFF35AA66)),
    );
    expect((await _pixel(transparent, 50, 50)).a, 0);
    expect(await _pixel(opaque, 50, 50), const _Pixel(53, 170, 102, 255));
    transparent.dispose();
    opaque.dispose();
    source.dispose();
  });
}

Future<ui.Image> _render(
  ui.Image source,
  ResolvedCameraState camera, {
  RenderTarget target = const RenderTarget.transparent(),
}) => const FrameRenderer().renderResolved(
  frame: ResolvedProjectFrame(
    time: TimelineTime.fromMicroseconds(1000),
    drawing: ResolvedDrawingFrame(
      localTime: TimelineTime.fromMicroseconds(1000),
      duration: TimelineDuration.fromMicroseconds(1000),
      sectionId: null,
      isHeld: true,
    ),
    camera: camera,
    activeAudio: const [],
    voiceGuide: null,
    markers: const [],
    isFinalFrame: false,
  ),
  project: _project(),
  drawing: source,
  hand: null,
  target: target,
);
Future<ui.Image> _renderPreview(
  ui.Image source,
  ResolvedCameraState camera,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const CameraVisualCompositor().paint(
    canvas: canvas,
    outputSize: ui.Size(100, 100),
    projectSize: ui.Size(100, 100),
    camera: camera,
    paintScene: (sceneCanvas, transform) {
      sceneCanvas.save();
      transform.apply(sceneCanvas);
      sceneCanvas.drawImage(source, ui.Offset.zero, ui.Paint());
      sceneCanvas.restore();
    },
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}

HandDrawProject _project() => HandDrawProject(
  canvasWidth: 100,
  canvasHeight: 100,
  durationSeconds: 1,
  drawingDurationSeconds: 1,
  startDelaySeconds: 0,
  endHoldSeconds: 0,
  revealWidth: 10,
  strokes: [
    DrawingStroke(
      id: 'stroke',
      name: 'Stroke',
      geometry: StrokePathGeometry(
        start: const ui.Offset(0, 0),
        segments: const [StrokeLineSegment(end: ui.Offset(1, 1))],
      ),
    ),
  ],
);
Future<ui.Image> _source() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 50, 100),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(50, 0, 50, 100),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}

Future<ui.Image> _quadrantSource() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final region in const [
    (ui.Rect.fromLTWH(0, 0, 50, 50), ui.Color(0xFFFF0000)),
    (ui.Rect.fromLTWH(50, 0, 50, 50), ui.Color(0xFF00FF00)),
    (ui.Rect.fromLTWH(0, 50, 50, 50), ui.Color(0xFF0000FF)),
    (ui.Rect.fromLTWH(50, 50, 50, 50), ui.Color(0xFFFFFF00)),
  ]) {
    canvas.drawRect(region.$1, ui.Paint()..color = region.$2);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}

Future<Uint8List> _rgba(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
))!.buffer.asUint8List();
Future<_Pixel> _pixel(ui.Image image, int x, int y) async {
  final bytes = await _rgba(image);
  final i = (y * image.width + x) * 4;
  return _Pixel(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
}

final class _Pixel {
  const _Pixel(this.r, this.g, this.b, this.a);
  final int r, g, b, a;
  @override
  bool operator ==(Object other) =>
      other is _Pixel &&
      r == other.r &&
      g == other.g &&
      b == other.b &&
      a == other.a;
  @override
  int get hashCode => Object.hash(r, g, b, a);
}
