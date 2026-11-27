import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

const _runProbe = bool.fromEnvironment('HANDDRAW_RUN_EXPORT_PROBE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profiles dense 1080p frame rendering and byte extraction',
    () async {
      final source = await _sourceImage(1920, 1080);
      final project = _denseProject();
      try {
        final warm = await const FrameRenderer().render(
          project: project,
          drawing: source,
          hand: null,
          progress: 0.5,
        );
        warm.dispose();

        final renderWatch = Stopwatch()..start();
        final frame = await const FrameRenderer().render(
          project: project,
          drawing: source,
          hand: null,
          progress: 0.55,
        );
        renderWatch.stop();

        final rawWatch = Stopwatch()..start();
        final raw = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
        rawWatch.stop();

        final pngWatch = Stopwatch()..start();
        final png = await frame.toByteData(format: ui.ImageByteFormat.png);
        pngWatch.stop();
        frame.dispose();

        // ignore: avoid_print
        print(
          'DENSE_EXPORT_PROBE paths=${project.strokes.length} '
          'render_ms=${renderWatch.elapsedMilliseconds} '
          'raw_ms=${rawWatch.elapsedMilliseconds} raw_bytes=${raw?.lengthInBytes} '
          'png_ms=${pngWatch.elapsedMilliseconds} png_bytes=${png?.lengthInBytes}',
        );
        expect(raw, isNotNull);
        expect(png, isNotNull);
      } finally {
        source.dispose();
      }
    },
    skip: _runProbe ? false : 'Opt-in dense export performance probe.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

HandDrawProject _denseProject() {
  final masks = List.generate(11, (index) {
    final column = index % 4;
    final row = index ~/ 4;
    final left = column * 0.25;
    final top = row * 0.33;
    return <ui.Offset>[
      ui.Offset(left, top),
      ui.Offset((left + 0.25).clamp(0, 1), top),
      ui.Offset((left + 0.25).clamp(0, 1), (top + 0.33).clamp(0, 1)),
      ui.Offset(left, (top + 0.33).clamp(0, 1)),
    ];
  });
  final strokes = List.generate(2190, (index) {
    final scene = index % masks.length;
    final x = 0.02 + (index % 100) / 104;
    final y = 0.02 + ((index ~/ 100) % 22) / 23;
    return DrawingStroke(
      id: 'dense-$index',
      name: 'Dense $index',
      sectionId: 'scene-$scene',
      points: [
        ui.Offset(x.clamp(0, 0.98), y.clamp(0, 0.98)),
        ui.Offset((x + 0.012).clamp(0, 1), (y + 0.006).clamp(0, 1)),
      ],
      clipPolygons: [masks[scene]],
    );
  });
  return HandDrawProject(
    canvasWidth: 1920,
    canvasHeight: 1080,
    durationSeconds: 6,
    drawingDurationSeconds: 6,
    strokes: strokes,
  );
}

Future<ui.Image> _sourceImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF315B88),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
