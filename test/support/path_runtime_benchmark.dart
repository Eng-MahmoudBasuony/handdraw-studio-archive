import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

/// Offline CPU/raster samples, not interactive FPS or native MOV throughput.
Future<Map<String, Object?>> benchmarkPathRuntime(
  ui.Image source,
  SmartPathAnalysis analysis,
  String output,
  String name,
) async {
  final planWatch = Stopwatch()..start();
  final plan = const AutoPathStrokePlanner().build(
    sections: analysis.sections,
    project: HandDrawProject(
      canvasWidth: source.width,
      canvasHeight: source.height,
      revealWidth: 24,
    ),
  );
  final planningUs = planWatch.elapsedMicroseconds;
  final project = HandDrawProject(
    canvasWidth: source.width,
    canvasHeight: source.height,
    durationSeconds: 4,
    drawingDurationSeconds: 4,
    startDelaySeconds: 0,
    endHoldSeconds: 0,
    revealWidth: 24,
    strokes: plan.strokes,
  );
  final rect = ui.Rect.fromLTWH(
    0,
    0,
    source.width.toDouble(),
    source.height.toDouble(),
  );
  final resolveUs = <int>[];
  final renderUs = <int>[];
  final hashes = <String>[];
  var differingBytes = 0;
  final original = (await source.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final sourceHash = sha256.convert(original).toString();
  final alphaCoverage = <double>[];
  final rgbaMeanAbsoluteError = <double>[];
  for (final progress in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99, 1.0]) {
    final watch = Stopwatch()..start();
    final snapshot = buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: rect,
      progress: progress,
      durationSeconds: 4,
      drawingDurationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      sectionTimings: project.sectionTimings,
      timingRect: rect,
    );
    resolveUs.add(watch.elapsedMicroseconds);
    watch.reset();
    final exported = await const FrameRenderer().render(
      project: project,
      drawing: source,
      hand: null,
      progress: progress,
    );
    renderUs.add(watch.elapsedMicroseconds);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (snapshot.drawingComplete) {
      canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    } else {
      drawRevealedArtwork(
        canvas: canvas,
        image: source,
        artworkRect: rect,
        snapshot: snapshot,
        defaultRevealWidth: project.revealWidth,
      );
    }
    final picture = recorder.endRecording();
    final preview = await picture.toImage(source.width, source.height);
    picture.dispose();
    final a = (await preview.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final b = (await exported.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) differingBytes++;
    }
    hashes.add(sha256.convert(b).toString());
    var expectedAlpha = 0, visibleAlpha = 0, absoluteError = 0;
    for (var i = 0; i < b.length; i++) {
      absoluteError += (b[i] - original[i]).abs();
      if (i % 4 == 3) {
        expectedAlpha += original[i];
        visibleAlpha += b[i] < original[i] ? b[i] : original[i];
      }
    }
    alphaCoverage.add(expectedAlpha == 0 ? 1 : visibleAlpha / expectedAlpha);
    rgbaMeanAbsoluteError.add(absoluteError / b.length);
    if (output.isNotEmpty && [0.25, 0.5, 0.99, 1.0].contains(progress)) {
      final bytes = await exported.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${File(output).parent.path}/runtime_frames/${name}_${(progress * 100).round()}.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    preview.dispose();
    exported.dispose();
  }
  expect(differingBytes, 0, reason: '$name preview/export raster parity');
  return {
    'sourceRgbaSha256': sourceHash,
    'alphaCoverageByProgress': alphaCoverage,
    'rgbaMaeByProgress': rgbaMeanAbsoluteError,
    'planningUs': planningUs,
    'strokeCount': plan.strokes.length,
    'timelineResolveSamplesUs': resolveUs,
    'offlineFrameRenderSamplesUs': renderUs,
    'progress': [0, .1, .25, .5, .75, .9, .99, 1],
    'frameSha256': hashes,
    'previewExportDifferingBytes': differingBytes,
    'nativeMovEncodeMs': null,
    'interactivePreviewFps': null,
  };
}
