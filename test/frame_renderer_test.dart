import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('camera-only timeline keeps static artwork visible in export', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFF2474E8),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final output = await const FrameRenderer().renderResolved(
      frame: ResolvedProjectFrame(
        time: TimelineTime.zero,
        drawing: null,
        camera: const ResolvedSingleCameraView(CameraView.identity()),
        activeAudio: const [],
        voiceGuide: null,
        markers: const [],
        isFinalFrame: false,
      ),
      project: HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        strokes: const [],
      ),
      drawing: source,
      hand: null,
    );
    final rgba = (await output.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final center = (50 * 100 + 50) * 4;

    expect(rgba.sublist(center, center + 4), [36, 116, 232, 255]);
    output.dispose();
    source.dispose();
  });

  test('the drawing is transparent before the first stroke starts', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      revealWidth: 12,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [ui.Offset(0.1, 0.5), ui.Offset(0.9, 0.5)],
        ),
      ],
    );

    final renderer = const FrameRenderer();
    final firstFrame = await renderer.render(
      project: project,
      drawing: source,
      hand: null,
      progress: 0,
    );
    final finalFrame = await renderer.render(
      project: project,
      drawing: source,
      hand: null,
      progress: 1,
    );
    final firstBytes = (await firstFrame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final finalBytes = (await finalFrame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;

    final firstAlpha = firstBytes.buffer.asUint8List()[3];
    var visiblePixels = 0;
    final rgba = finalBytes.buffer.asUint8List();
    for (var index = 3; index < rgba.length; index += 4) {
      if (rgba[index] > 0) visiblePixels++;
    }

    expect(firstAlpha, 0);
    expect(visiblePixels, greaterThan(500));
    firstFrame.dispose();
    finalFrame.dispose();
    source.dispose();
  });

  test('MOV source frame keeps the hand after drawing when enabled', () async {
    Future<ui.Image> createSolidImage(int size, ui.Color color) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        ui.Paint()..color = color,
      );
      return recorder.endRecording().toImage(size, size);
    }

    int redPixels(ByteData bytes) {
      final rgba = bytes.buffer.asUint8List();
      var count = 0;
      for (var index = 0; index < rgba.length; index += 4) {
        if (rgba[index] > 200 &&
            rgba[index + 1] < 80 &&
            rgba[index + 2] < 80 &&
            rgba[index + 3] > 0) {
          count++;
        }
      }
      return count;
    }

    final drawing = await createSolidImage(100, const ui.Color(0xFF2474E8));
    final hand = await createSolidImage(20, const ui.Color(0xFFFF0000));
    final stroke = DrawingStroke(
      id: 'final-stroke',
      name: 'Final stroke',
      sectionId: 'final',
      points: const [ui.Offset(.2, .5), ui.Offset(.5, .5)],
    );
    HandDrawProject project(bool keepVisible) => HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1.5,
      drawingDurationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: .5,
      handScale: .4,
      penTip: const ui.Offset(.5, .5),
      strokes: [stroke],
      sectionTimings: {
        'section:final': SectionTiming(
          animationDurationSeconds: 1,
          keepHandVisibleAfterDrawing: keepVisible,
        ),
      },
    );

    final renderer = const FrameRenderer();
    final held = await renderer.render(
      project: project(true),
      drawing: drawing,
      hand: hand,
      progress: 1,
    );
    final hidden = await renderer.render(
      project: project(false),
      drawing: drawing,
      hand: hand,
      progress: 1,
    );
    final heldBytes = (await held.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final hiddenBytes = (await hidden.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;

    expect(redPixels(heldBytes), greaterThan(100));
    expect(redPixels(hiddenBytes), 0);

    held.dispose();
    hidden.dispose();
    drawing.dispose();
    hand.dispose();
  });

  test('directional wipe never reveals artwork ahead of the pen tip', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'auto-reveal',
          name: 'Auto Reveal',
          points: const [ui.Offset(0, 0.5), ui.Offset(1, 0.5)],
          revealOnly: true,
          revealStyle: RevealMaskStyle.directionalWipe,
          clipBounds: const ui.Rect.fromLTWH(0, 0, 1, 1),
        ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 0.5,
    );
    final rgba = (await frame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    int alphaAt(int x) => rgba[(50 * 100 + x) * 4 + 3];

    expect(alphaAt(10), 255);
    expect(alphaAt(49), 255);
    expect(alphaAt(51), 0);
    expect(alphaAt(90), 0);
    frame.dispose();
    source.dispose();
  });

  test(
    'large active manual brush stops at the nib instead of leading it',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      final source = await recorder.endRecording().toImage(100, 100);
      final project = HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        durationSeconds: 1,
        drawingDurationSeconds: 1,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        strokes: [
          DrawingStroke(
            id: 'manual-broad-reveal',
            name: 'Manual broad reveal',
            points: const [ui.Offset(0.1, 0.5), ui.Offset(0.9, 0.5)],
            revealWidth: 80,
          ),
        ],
      );

      final snapshot = buildTimelineSnapshot(
        strokes: project.strokes,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        progress: 0.5,
        durationSeconds: 1,
        drawingDurationSeconds: 1,
      );
      expect(snapshot.handPosition.dx, closeTo(50, 0.01));
      expect(snapshot.revealedPaths.single.activeBrushDirection, isNotNull);

      final frame = await const FrameRenderer().render(
        project: project,
        drawing: source,
        hand: null,
        progress: 0.5,
      );
      final rgba = (await frame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      int alphaAt(int x) => rgba[(50 * 100 + x) * 4 + 3];

      expect(alphaAt(45), 255);
      expect(alphaAt(55), 0);
      expect(alphaAt(80), 0);
      frame.dispose();
      source.dispose();
    },
  );

  test('right-to-left wipe also stops exactly at the pen tip', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'rtl-auto-reveal',
          name: 'RTL Auto Reveal',
          points: const [ui.Offset(1, 0.5), ui.Offset(0, 0.5)],
          revealOnly: true,
          revealStyle: RevealMaskStyle.directionalWipe,
          clipBounds: const ui.Rect.fromLTWH(0, 0, 1, 1),
        ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 0.5,
    );
    final rgba = (await frame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    int alphaAt(int x) => rgba[(50 * 100 + x) * 4 + 3];

    expect(alphaAt(90), 255);
    expect(alphaAt(51), 255);
    expect(alphaAt(49), 0);
    expect(alphaAt(10), 0);
    frame.dispose();
    source.dispose();
  });

  test('one automatic section cannot reveal the next section early', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      revealWidth: 40,
      strokes: [
        DrawingStroke(
          id: 'title',
          name: 'Title',
          points: const [ui.Offset(0.1, 0.35), ui.Offset(0.9, 0.35)],
        ),
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [ui.Offset(0.1, 0.55), ui.Offset(0.9, 0.55)],
        ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 0.45,
    );
    final data = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgba = data.buffer.asUint8List();
    int alphaAt(int x, int y) => rgba[(y * 100 + x) * 4 + 3];

    expect(alphaAt(50, 35), greaterThan(0));
    expect(alphaAt(50, 52), 0);

    frame.dispose();
    source.dispose();
  });

  test('artwork masks cannot reveal an excluded text region', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'artwork',
          name: 'Artwork',
          points: const [ui.Offset(0.05, 0.5), ui.Offset(0.95, 0.5)],
          revealWidth: 80,
          clipBounds: const ui.Rect.fromLTWH(0, 0, 1, 1),
          exclusionBounds: const [ui.Rect.fromLTWH(0.4, 0.4, 0.2, 0.2)],
        ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 0.9,
    );
    final data = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final rgba = data.buffer.asUint8List();
    int alphaAt(int x, int y) => rgba[(y * 100 + x) * 4 + 3];

    expect(alphaAt(20, 50), greaterThan(0));
    expect(alphaAt(50, 50), 0);
    frame.dispose();
    source.dispose();
  });

  test('reveal preserves the original artwork colors', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(10, 20, 80, 60),
      ui.Paint()..color = const ui.Color.fromARGB(255, 24, 119, 210),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'outline',
          name: 'Outline',
          points: const [ui.Offset(0.1, 0.5), ui.Offset(0.9, 0.5)],
          revealWidth: 80,
          clipBounds: const ui.Rect.fromLTWH(0, 0, 1, 1),
        ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 1,
    );
    final sourceRgba = (await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final outputRgba = (await frame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final center = (50 * 100 + 50) * 4;

    expect(
      outputRgba.sublist(center, center + 4),
      sourceRgba.sublist(center, center + 4),
    );
    expect(outputRgba.sublist(center, center + 4), [24, 119, 210, 255]);
    frame.dispose();
    source.dispose();
  });

  test('overlapping masks do not accumulate translucent artwork', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color.fromARGB(64, 24, 119, 210),
    );
    final source = await recorder.endRecording().toImage(100, 100);
    final project = HandDrawProject(
      canvasWidth: 100,
      canvasHeight: 100,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        for (var index = 0; index < 3; index++)
          DrawingStroke(
            id: 'overlap-$index',
            name: 'Overlap $index',
            points: const [ui.Offset(0.1, 0.5), ui.Offset(0.9, 0.5)],
            revealWidth: 40,
            clipBounds: const ui.Rect.fromLTWH(0, 0, 1, 1),
          ),
      ],
    );

    final frame = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: 1,
    );
    final sourceRgba = (await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final outputRgba = (await frame.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final center = (50 * 100 + 50) * 4;

    expect(
      outputRgba.sublist(center, center + 4),
      sourceRgba.sublist(center, center + 4),
    );
    expect(outputRgba[center + 3], 64);
    frame.dispose();
    source.dispose();
  });

  test(
    'final hold is pixel-identical to the complete source artwork',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          const ui.Rect.fromLTWH(12, 18, 76, 54),
          const ui.Radius.circular(9),
        ),
        ui.Paint()..color = const ui.Color.fromARGB(107, 255, 238, 197),
      );
      canvas.drawLine(
        const ui.Offset(18, 65),
        const ui.Offset(82, 65),
        ui.Paint()
          ..color = const ui.Color(0xFF24211F)
          ..strokeWidth = 7,
      );
      final source = await recorder.endRecording().toImage(100, 100);
      final project = HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        durationSeconds: 1,
        startDelaySeconds: 0,
        endHoldSeconds: 0.2,
        strokes: [
          DrawingStroke(
            id: 'narrow-mask',
            name: 'Narrow mask',
            points: const [ui.Offset(0.25, 0.45), ui.Offset(0.75, 0.45)],
            revealWidth: 8,
          ),
        ],
      );

      final frame = await const FrameRenderer().render(
        project: project,
        drawing: source,
        hand: null,
        progress: 0.9,
      );
      final sourceRgba = (await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final outputRgba = (await frame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      expect(outputRgba, orderedEquals(sourceRgba));
      frame.dispose();
      source.dispose();
    },
  );
}
