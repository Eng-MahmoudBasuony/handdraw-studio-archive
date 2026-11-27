import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('lift progress is available only between disconnected strokes', () {
    final strokes = [
      DrawingStroke(
        id: 'a',
        name: 'a',
        points: const [ui.Offset(.1, .1), ui.Offset(.2, .1)],
      ),
      DrawingStroke(
        id: 'b',
        name: 'b',
        points: const [ui.Offset(.8, .8), ui.Offset(.9, .8)],
      ),
    ];
    var lifts = 0;
    for (var i = 0; i < 101; i++) {
      final frame = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        progress: i / 100,
        durationSeconds: 6,
      );
      if (frame.phase == TimelinePhase.travel) {
        lifts++;
        expect(frame.penLiftProgress, inInclusiveRange(0, 1));
        expect(
          frame.penTravelDistance,
          closeTo(const ui.Offset(60, 70).distance, .000001),
        );
        expect(frame.penIsDrawing, isFalse);
      } else {
        expect(frame.penLiftProgress, isNull);
      }
    }
    expect(lifts, greaterThan(0));
  });

  test(
    'authored coverage never reveals an undrawn corner at completion',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawColor(const ui.Color(0x80ff0000), ui.BlendMode.src);
      final pic = recorder.endRecording(), source = await pic.toImage(100, 100);
      pic.dispose();
      final project = HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        strokes: [
          DrawingStroke(
            id: 'a',
            name: 'a',
            points: const [ui.Offset(.1, .5), ui.Offset(.9, .5)],
            revealWidth: 8,
          ),
        ],
      );
      for (final legacy in [false, true]) {
        final result = await FrameRenderer().render(
          project: project.copyWith(
            imageAnimationEffect: legacy ? 'legacy' : 'drawPaint',
          ),
          drawing: source,
          hand: null,
          progress: 1,
        );
        final bytes = (await result.toByteData())!.buffer.asUint8List();
        expect(bytes[3], legacy ? 128 : 0);
        expect(bytes[(50 * 100 + 50) * 4 + 3], 128);
        result.dispose();
      }
      source.dispose();
    },
  );
  test(
    'quick paint fills each outlined region once and preserves its holes',
    () async {
      final source = img.Image(width: 240, height: 120, numChannels: 4);
      for (final left in [10, 130]) {
        img.fillRect(
          source,
          x1: left,
          y1: 10,
          x2: left + 99,
          y2: 109,
          color: img.ColorRgba8(20, 180, 220, 128),
        );
        img.fillRect(
          source,
          x1: left + 40,
          y1: 50,
          x2: left + 59,
          y2: 69,
          color: img.ColorRgba8(0, 0, 0, 0),
          alphaBlend: false,
        );
      }
      final encoded = img.encodePng(source);
      final plan = const RegionDrawingPlanner(quickPaint: true).build(encoded);
      final ordered = plan.ordered(ImageDrawingOrder.regionFirst);
      expect(
        ordered.where((s) => s.role == ImageStrokeRole.paint),
        hasLength(2),
      );
      final completed = <int>{};
      for (final item in ordered) {
        expect(
          completed.contains(item.region),
          isFalse,
          reason: 'Finish each region before moving to the next one',
        );
        if (item.role == ImageStrokeRole.paint) {
          expect(item.stroke.points, hasLength(2));
          completed.add(item.region);
        }
      }
      final codec = await ui.instantiateImageCodec(encoded);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final project = HandDrawProject(
        canvasWidth: 240,
        canvasHeight: 120,
        strokes: ordered.map((s) => s.stroke).toList(),
      );
      final frame = await const FrameRenderer(
        revealSourceAtCompletion: false,
      ).render(project: project, drawing: image, hand: null, progress: 1);
      final pixels = (await frame.toByteData())!.buffer.asUint8List();
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 240; x++) {
          // Image filtering antialiases the source boundaries. Compare the
          // interiors and holes independently of that existing edge sampling.
          final alpha = source.getPixel(x, y).a;
          if (x < 2 || y < 2 || x >= 238 || y >= 118) continue;
          if ([
            source.getPixel(x - 2, y).a,
            source.getPixel(x + 2, y).a,
            source.getPixel(x, y - 2).a,
            source.getPixel(x, y + 2).a,
          ].any((value) => value != alpha)) {
            continue;
          }
          expect(
            pixels[(y * 240 + x) * 4 + 3],
            source.getPixel(x, y).a,
            reason: 'Original alpha at ($x, $y)',
          );
        }
      }
      frame.dispose();
      image.dispose();
    },
  );
  test('regional masks retain holes, alpha and thin line interiors', () async {
    final source = img.Image(width: 80, height: 60, numChannels: 4);
    img.fillRect(
      source,
      x1: 10,
      y1: 10,
      x2: 69,
      y2: 49,
      color: img.ColorRgba8(220, 40, 60, 128),
    );
    img.fillRect(
      source,
      x1: 25,
      y1: 20,
      x2: 54,
      y2: 39,
      color: img.ColorRgba8(0, 0, 0, 0),
      alphaBlend: false,
    );
    final encoded = img.encodePng(source);
    final plan = const RegionDrawingPlanner().build(encoded);
    expect(plan.strokes, isNotEmpty);
    final codec = await ui.instantiateImageCodec(encoded),
        image = (await codec.getNextFrame()).image;
    codec.dispose();
    final project = HandDrawProject(
      canvasWidth: 80,
      canvasHeight: 60,
      strokes: plan.strokes.map((s) => s.stroke).toList(),
    );
    final frame = await const FrameRenderer(
      revealSourceAtCompletion: false,
    ).render(project: project, drawing: image, hand: null, progress: 1);
    final data = (await frame.toByteData())!.buffer.asUint8List();
    expect(data[(30 * 80 + 40) * 4 + 3], 0);
    expect(data[(15 * 80 + 15) * 4 + 3], 128);
    expect(data[3], 0);
    image.dispose();
    frame.dispose();
  });
}
