import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real-image review videos',
    () async {
      final output = Directory(
        const String.fromEnvironment(
          'HANDDRAW_LAB_OUTPUT',
          defaultValue: 'build/drawing_lab_review',
        ),
      )..createSync(recursive: true);
      final metrics = <Map<String, Object?>>[];
      for (final file in ['04-build-fails', '00-title']) {
        if (const String.fromEnvironment('HANDDRAW_LAB_IMAGE').isNotEmpty &&
            file != const String.fromEnvironment('HANDDRAW_LAB_IMAGE')) {
          continue;
        }
        final encoded = File('test/fixtures/$file.png').readAsBytesSync();
        final plan = const RegionDrawingPlanner(
          quickPaint: bool.fromEnvironment('HANDDRAW_LAB_QUICK_PAINT'),
        ).build(encoded);
        final codec = await ui.instantiateImageCodec(encoded),
            source = (await codec.getNextFrame()).image;
        codec.dispose();
        for (final order in ImageDrawingOrder.values) {
          if (const String.fromEnvironment('HANDDRAW_LAB_ORDER').isNotEmpty &&
              order.name !=
                  const String.fromEnvironment('HANDDRAW_LAB_ORDER')) {
            continue;
          }
          final strokes = plan.ordered(order);
          final project = HandDrawProject(
            canvasWidth: source.width,
            canvasHeight: source.height,
            durationSeconds: 12,
            drawingDurationSeconds: 12,
            startDelaySeconds: 0,
            endHoldSeconds: 0,
            strokes: strokes.map((s) => s.stroke).toList(),
          );
          final out = '${output.path}/$file-${order.name}';
          final encoder = await Process.start('/opt/homebrew/bin/ffmpeg', [
            '-y',
            '-loglevel',
            'error',
            '-f',
            'rawvideo',
            '-pixel_format',
            'rgba',
            '-video_size',
            '${source.width}x${source.height}',
            '-framerate',
            '30',
            '-i',
            'pipe:0',
            '-vf',
            'format=rgb24',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-crf',
            '18',
            '-pix_fmt',
            'yuv420p',
            '$out.mp4',
          ]);
          final errors = encoder.stderr.transform(utf8.decoder).join();
          const renderer = FrameRenderer(
            revealSourceAtCompletion: false,
            rasterFilterQuality: ui.FilterQuality.none,
          );
          final watch = Stopwatch()..start();
          final frameTimes = <int>[];
          for (var i = 0; i < 360; i++) {
            final frameWatch = Stopwatch()..start();
            final frame = await renderer.render(
              project: project,
              drawing: source,
              hand: null,
              progress: i / 359,
            );
            if ([0, 36, 108, 180, 216, 288, 355, 358, 359].contains(i)) {
              final png = (await frame.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File('$out-$i.png').writeAsBytes(png.buffer.asUint8List());
            }
            // Composite against white only for review MP4; actual MOV is RGBA.
            final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
            canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
            canvas.drawImage(frame, ui.Offset.zero, ui.Paint());
            final picture = recorder.endRecording(),
                white = await picture.toImage(source.width, source.height);
            picture.dispose();
            encoder.stdin.add((await white.toByteData())!.buffer.asUint8List());
            await encoder.stdin.flush();
            white.dispose();
            frame.dispose();
            frameTimes.add(frameWatch.elapsedMilliseconds);
          }
          await encoder.stdin.close();
          expect(await encoder.exitCode, 0, reason: await errors);
          metrics.add({
            'image': file,
            'order': order.name,
            'analysis_ms': plan.analysisMilliseconds,
            'render_encode_ms': watch.elapsedMilliseconds,
            'strokes': strokes.length,
            'frameTimesMs': frameTimes,
            'rss_bytes': ProcessInfo.currentRss,
            'max_rss_bytes': ProcessInfo.maxRss,
          });
          // ignore: avoid_print
          print(Map.of(metrics.last)..remove('frameTimesMs'));
        }
        source.dispose();
      }
      await File(
        '${output.path}/metrics.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
    },
    skip: !const bool.fromEnvironment('HANDDRAW_LAB_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
