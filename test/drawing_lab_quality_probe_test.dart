import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'source-backed real image coverage without completion substitution',
    () async {
      await Directory('build/drawing_lab_review').create(recursive: true);
      for (final file in ['04-build-fails', '00-title']) {
        final bytes = File('test/fixtures/$file.png').readAsBytesSync();
        final plan = const RegionDrawingPlanner(
          quickPaint: bool.fromEnvironment('HANDDRAW_LAB_QUICK_PAINT'),
        ).build(bytes);
        if (file == '00-title') {
          final glyphs = <int, List<ui.Offset>>{};
          for (final s in plan.strokes) {
            final points = s.stroke.points;
            final ys = points.map((p) => p.dy);
            if (ys.reduce(math.min) > .07 &&
                ys.reduce(math.max) < .165 &&
                ys.reduce(math.max) - ys.reduce(math.min) > .015) {
              expect(
                s.role,
                ImageStrokeRole.line,
                reason: 'Display letters must not be outlined and repainted',
              );
              (glyphs[s.region] ??= []).addAll(points);
            }
          }
          final lefts = glyphs.values
              .map((points) => points.map((p) => p.dx).reduce(math.min))
              .toList();
          expect(lefts.length, greaterThanOrEqualTo(10));
          for (var i = 1; i < lefts.length; i++) {
            expect(
              lefts[i],
              greaterThan(lefts[i - 1]),
              reason: 'Title letters follow reading order',
            );
          }
        }

        final codec = await ui.instantiateImageCodec(bytes),
            image = (await codec.getNextFrame()).image;
        codec.dispose();
        var tiny = 0;
        for (final s in plan.strokes) {
          final pts = s.stroke.points;
          final w =
              pts.map((p) => p.dx).reduce(math.max) -
              pts.map((p) => p.dx).reduce(math.min);
          final h =
              pts.map((p) => p.dy).reduce(math.max) -
              pts.map((p) => p.dy).reduce(math.min);
          if (math.max(w * image.width, h * image.height) <= 4) tiny++;
        }
        final frame =
            await const FrameRenderer(
              revealSourceAtCompletion: false,
              rasterFilterQuality: ui.FilterQuality.none,
            ).render(
              project: HandDrawProject(
                canvasWidth: image.width,
                canvasHeight: image.height,
                strokes: plan.strokes.map((s) => s.stroke).toList(),
              ),
              drawing: image,
              hand: null,
              progress: 1,
            );
        final original = (await image.toByteData())!.buffer.asUint8List(),
            actual = (await frame.toByteData())!.buffer.asUint8List();
        var foreground = 0, missing = 0;
        double totalError = 0;
        for (var p = 0; p < original.length; p += 4) {
          if (original[p + 3] > 0) {
            foreground++;
            if (actual[p + 3] < original[p + 3] - 12) missing++;
            for (var c = 0; c < 4; c++) {
              totalError += (original[p + c] - actual[p + c]).abs();
            }
          } else {
            expect(actual[p + 3], 0);
          }
        }
        // A coverage metric is not a motion-quality claim.
        expect(missing / foreground, lessThan(.002));
        await File("build/drawing_lab_review/$file-coverage.png").writeAsBytes(
          (await frame.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        // ignore: avoid_print
        print({
          'image': file,
          'strokes': plan.strokes.length,
          'tiny': tiny,
          'missingFraction': missing / foreground,
          'rgbaMAE': totalError / (foreground * 4),
          'analysisMs': plan.analysisMilliseconds,
        });
        frame.dispose();
        image.dispose();
      }
    },
  );
}
