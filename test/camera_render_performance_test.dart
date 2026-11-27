import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

const _run = bool.fromEnvironment('HANDDRAW_RUN_CAMERA_RENDER_BENCHMARK');
void main() {
  test(
    'camera renderer identity move and fade benchmark',
    () async {
      final source = await _source();
      for (final size in [(1280, 720), (1920, 1080), (3840, 2160)]) {
        final project = _project(size.$1, size.$2);
        for (final mode in ['identity', 'move', 'fade']) {
          final samples = <int>[];
          for (var i = 0; i < 3; i++) {
            final watch = Stopwatch()..start();
            final image = await const FrameRenderer().renderResolved(
              frame: _frame(mode),
              project: project,
              drawing: source,
              hand: null,
            );
            watch.stop();
            samples.add(watch.elapsedMicroseconds);
            image.dispose();
          }
          samples.sort();
          final rss = ProcessInfo.currentRss;
          final mean = samples.reduce((a, b) => a + b) / samples.length;
          // ignore: avoid_print
          print(
            'CAMERA_RENDER mode=debug_jit size=${size.$1}x${size.$2} camera=$mode mean_us=$mean p95_us=${samples.last} rss_bytes=$rss',
          );
        }
      }
      source.dispose();
    },
    skip: !_run
        ? 'Opt-in with HANDDRAW_RUN_CAMERA_RENDER_BENCHMARK=true'
        : null,
  );
}

ResolvedProjectFrame _frame(String mode) {
  const from = CameraView.identity();
  const to = CameraView(centerX: .35, centerY: .45, viewportWidth: .65);
  final camera = switch (mode) {
    'fade' => const ResolvedCameraBlend(
      fromView: from,
      toView: to,
      targetOpacity: .5,
    ),
    'move' => const ResolvedSingleCameraView(to),
    _ => const ResolvedSingleCameraView(from),
  };
  return ResolvedProjectFrame(
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
  );
}

HandDrawProject _project(int width, int height) => HandDrawProject(
  canvasWidth: width,
  canvasHeight: height,
  durationSeconds: 1,
  drawingDurationSeconds: 1,
  startDelaySeconds: 0,
  endHoldSeconds: 0,
  revealWidth: 10,
  strokes: [
    DrawingStroke(
      id: 's',
      name: 's',
      geometry: StrokePathGeometry(
        start: ui.Offset.zero,
        segments: const [StrokeLineSegment(end: ui.Offset(1, 1))],
      ),
    ),
  ],
);
Future<ui.Image> _source() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 36),
    ui.Paint()..color = const ui.Color(0xFF4488DD),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 36);
  picture.dispose();
  return image;
}
