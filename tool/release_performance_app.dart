// Standalone native Release-only measurement. No test binding or fake clock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/core/platform/native_launch_service.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/export/infrastructure/video_export_service.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/memory_hand_library_repository.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

import '../test/support/legacy_editor_state_fixture.dart';

const screenshotsOnly = bool.fromEnvironment('PERF_SCREENSHOTS_ONLY');
const label = String.fromEnvironment('PERF_LABEL', defaultValue: 'baseline');
const sourcePath = String.fromEnvironment(
  'PERF_SOURCE',
  defaultValue: '/tmp/source.png',
);
final activeEditor = ValueNotifier<EditorCubit?>(null);
final editorCaptureKey = GlobalKey();
final report = <String, Object?>{
  'label': label,
  'mode': 'release',
  'pid': pid,
  'startedUtc': DateTime.now().toUtc().toIso8601String(),
  'previewScope':
      'Production EditorScreen at actual native viewport; project resolution is not viewport resolution',
  'cases': <Map<String, Object?>>[],
};
late Directory output;

Future<void> flush() async {
  final file = File('${output.path}/report.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
}

void log(String message) => stdout.writeln('RELEASE_PERF $message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    throw StateError('This benchmark MUST run in Release mode.');
  }
  output = Directory('${Directory.systemTemp.path}/release-perf-$label');
  await output.create(recursive: true);
  report['output'] = output.path;
  await flush();
  runApp(
    MaterialApp(
      theme: AppThemeFactory.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ValueListenableBuilder<EditorCubit?>(
        valueListenable: activeEditor,
        builder: (context, editor, _) => editor == null
            ? const Scaffold(
                body: Center(
                  child: Text('Preparing Release performance measurement…'),
                ),
              )
            : RepaintBoundary(
                key: editorCaptureKey,
                child: EditorScreen(key: ObjectKey(editor), cubit: editor),
              ),
      ),
    ),
  );
  await nextFrame();
  await NativeLaunchService.notifyFirstFrameRendered();
  log('output=${output.path}');
  try {
    if (screenshotsOnly) {
      await archiveScreenshots();
      report['status'] = 'complete';
      await flush();
      log('screenshots complete');
      exit(0);
    }
    final encoded = await File(sourcePath).readAsBytes();
    report['sourcePath'] = sourcePath;
    report['sourceSha256'] = sha256.convert(encoded).toString();
    final planning = Stopwatch()..start();
    final realistic = const RegionDrawingPlanner(quickPaint: true)
        .build(encoded)
        .ordered(ImageDrawingOrder.regionFirst)
        .map((s) => s.stroke)
        .toList();
    report['realisticPlanningMs'] = planning.elapsedMilliseconds;
    report['realisticStrokeCount'] = realistic.length;
    if (realistic.isEmpty) throw StateError('Realistic fixture has no paths');
    for (final fixture in ['realistic', 'dense2190']) {
      for (final size in [
        const ui.Size(1920, 1080),
        const ui.Size(3840, 2160),
      ]) {
        await runCase(fixture, size, encoded, realistic);
      }
    }
    report['status'] = 'complete';
    await flush();
    log('complete');
    exit(0);
  } catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error';
    report['stack'] = '$stack';
    await flush();
    log('FAILED $error');
    exit(1);
  }
}

Future<void> runCase(
  String fixture,
  ui.Size size,
  Uint8List realisticBytes,
  List<DrawingStroke> realisticStrokes,
) async {
  final id = '$fixture-${size.width.toInt()}x${size.height.toInt()}';
  final directory = Directory('${output.path}/$id');
  await directory.create(recursive: true);
  clearIdleRevealRenderingCaches();
  final image = fixture == 'realistic'
      ? await decode(realisticBytes)
      : await denseImage(size);
  final bytes = fixture == 'realistic'
      ? realisticBytes
      : (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
  final project = HandDrawProject(
    canvasWidth: size.width.toInt(),
    canvasHeight: size.height.toInt(),
    durationSeconds: 6,
    drawingDurationSeconds: 6,
    startDelaySeconds: 0,
    endHoldSeconds: 0,
    frameRate: 30,
    drawingImageBase64: base64Encode(bytes),
    drawingSourceBase64: base64Encode(bytes),
    imageAnimationEffect: fixture == 'realistic' ? 'drawPaint' : 'legacy',
    strokes: fixture == 'realistic' ? realisticStrokes : denseStrokes(),
  );
  final sourceFile = File('${directory.path}/source.png');
  await sourceFile.writeAsBytes(bytes, flush: true);
  final initialState = testEditorState(project: project, drawingImage: image);
  // Legacy test fixtures intentionally use fake external assets. Native runtime
  // snapshots verify files and hashes, so supply real benchmark-owned assets.
  final document = initialState.document.copyWith(
    assets: [
      for (final asset in initialState.document.assets)
        asset.kind == ProjectAssetKind.artwork
            ? asset.copyWith(
                contentHash: 'sha256:${sha256.convert(bytes)}',
                externalLocator: ExternalAssetLocator(
                  pathHint: sourceFile.path,
                ),
                mediaType: 'image/png',
              )
            : asset,
    ],
  );
  final editor = EditorCubit(
    initialState: initialState.copyWith(
      documentState: initialState.documentState.replace(document),
    ),
    handLibraryRepository: MemoryHandLibraryRepository(),
  );
  final entry = <String, Object?>{
    'id': id,
    'status': 'preparing',
    'canvasWidth': project.canvasWidth,
    'canvasHeight': project.canvasHeight,
    'frameRate': 30,
    'durationSeconds': 6,
    'strokeCount': project.strokes.length,
    'sourceSha256': sha256.convert(bytes).toString(),
    'previewRuns': <Map<String, Object?>>[],
  };
  (report['cases']! as List<Map<String, Object?>>).add(entry);
  await flush();
  log('$id preparing');
  try {
    await editor.initializeHandLibrary();
    if (editor.state.handImage == null) {
      throw StateError('Built-in hand failed to load');
    }
    final preflightWatch = Stopwatch()..start();
    final preflight = await editor.acquireRenderSnapshot(
      kind: StagedAssetReferenceKind.preview,
    );
    await preflight.release();
    entry['snapshotPreflightMs'] = preflightWatch.elapsedMilliseconds;
    entry['verifiedSourcePath'] = sourceFile.path;
    await flush();
    log(
      '$id verified preview snapshot in ${preflightWatch.elapsedMilliseconds}ms',
    );
    activeEditor.value = editor;
    await nextFrame();
    await waitUntil(
      () => button('canvas-preview-toggle')?.onPressed != null,
      stage: 'mount-enabled-preview',
    );
    entry['viewport'] = viewport();
    for (final run in ['firstPlayback', 'warmReplay']) {
      entry['status'] = 'preview-$run';
      await flush();
      log('$id preview $run');
      (entry['previewRuns']! as List<Map<String, Object?>>).add(
        await measurePreview(run),
      );
      await flush();
    }
    entry['status'] = 'unmeasured-ui-screenshots';
    await flush();
    final overviewPath = '${directory.path}/editor-overview.png';
    await captureEditor(overviewPath);
    final control = button('canvas-preview-toggle');
    if (control?.onPressed == null) {
      throw StateError('Screenshot playback is unavailable');
    }
    control!.onPressed!();
    await waitUntil(playing, stage: 'screenshot-start-playing');
    await Future<void>.delayed(const Duration(seconds: 3));
    await pauseForScreenshot();
    final previewPath = '${directory.path}/editor-preview.png';
    await captureEditor(previewPath);
    final stop = button('canvas-preview-stop');
    stop?.onPressed?.call();
    await waitUntil(() => !playing(), stage: 'screenshot-stop');
    await nextFrame();
    entry['uiScreenshots'] = {
      'overview': overviewPath,
      'drawingPreview': previewPath,
      'pixelRatio': 2,
      'includedInTimingSamples': false,
    };
    log('$id captured native editor screenshots outside measurement');
    entry['status'] = 'quality-captures';
    await flush();
    final snapshot = await editor.acquireRenderSnapshot(
      kind: StagedAssetReferenceKind.export,
    );
    try {
      final captures = <Map<String, Object?>>[];
      for (final progress in [.1, .5, .9]) {
        final frame = await const FrameRenderer().render(
          project: snapshot.project,
          drawing: snapshot.drawing!,
          drawingRevealBase: snapshot.drawingRevealBase,
          svgRevealLayers: snapshot.svgRevealLayers,
          hand: snapshot.hand,
          progress: progress,
        );
        try {
          final png = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
          final rgba = (await frame.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final path =
              '${directory.path}/frame-${(progress * 100).round()}.png';
          await File(path).writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
          captures.add({
            'progress': progress,
            'path': path,
            'rgbaSha256': sha256
                .convert(
                  rgba.buffer.asUint8List(
                    rgba.offsetInBytes,
                    rgba.lengthInBytes,
                  ),
                )
                .toString(),
          });
        } finally {
          frame.dispose();
        }
      }
      entry['qualityCaptures'] = captures;
      entry['status'] = 'exporting';
      await flush();
      log('$id exporting 180 frames');
      final events = <Map<String, Object?>>[];
      entry['exportEvents'] = events;
      final watch = Stopwatch()..start();
      final path = await const VideoExportService().exportProRes4444(
        project: snapshot.project,
        timeline: snapshot.timeline,
        frameRate: FrameRate(numerator: 30),
        transparent: true,
        drawing: snapshot.drawing!,
        drawingRevealBase: snapshot.drawingRevealBase,
        svgRevealLayers: snapshot.svgRevealLayers,
        hand: snapshot.hand,
        destinationPath: '${directory.path}/movie.mov',
        onTimingMetrics: (metrics) {
          entry['exportStageTotalsUs'] = {
            'frameCount': metrics.frameCount,
            'render': metrics.renderMicroseconds,
            'readback': metrics.readbackMicroseconds,
            'nativeAppend': metrics.nativeAppendMicroseconds,
          };
          log(
            '$id export stage totals: ${jsonEncode(entry['exportStageTotalsUs'])}',
          );
        },
        onProgress: (update) {
          events.add({
            'elapsedUs': watch.elapsedMicroseconds,
            'stage': update.stage.name,
            'frame': update.currentFrame,
            'totalFrames': update.totalFrames,
            'progress': update.progress,
          });
          if ((update.currentFrame ?? -1) % 30 == 0 ||
              update.stage == VideoExportStage.complete) {
            log(
              '$id ${update.stage.name} frame=${update.currentFrame} elapsedMs=${watch.elapsedMilliseconds}',
            );
          }
        },
      );
      watch.stop();
      if (path == null || !await File(path).exists()) {
        throw StateError('Export produced no MOV');
      }
      entry['export'] = {
        'path': path,
        'elapsedMs': watch.elapsedMilliseconds,
        'bytes': await File(path).length(),
        'transparent': true,
        'quality': 'full',
      };
    } finally {
      await snapshot.release();
    }
    entry['status'] = 'complete';
    log('$id complete');
  } catch (error) {
    entry['status'] = 'failed';
    entry['error'] = '$error';
    rethrow;
  } finally {
    activeEditor.value = null;
    await nextFrame();
    final originalHand = editor.state.handImage;
    await editor.close();
    originalHand?.dispose();
    image.dispose();
    await flush();
  }
}

Future<void> nextFrame() async {
  SchedulerBinding.instance.scheduleFrame();
  await SchedulerBinding.instance.endOfFrame.timeout(
    const Duration(seconds: 10),
  );
}

Future<void> pauseForScreenshot() async {
  if (playing()) {
    button('canvas-preview-toggle')?.onPressed?.call();
    await waitUntil(() => !playing(), stage: 'screenshot-pause');
  }
  await nextFrame();
}

Future<void> captureEditor(String path) async {
  log('capture begin $path');
  await pauseForScreenshot();
  final messages = previewDiagnostics()['snackbars'] as List;
  if (messages.isNotEmpty) {
    throw StateError('Cannot publish screenshot with an active alert');
  }
  var blocked = false;
  void inspect(Element element) {
    final widget = element.widget;
    if (widget is Dialog) blocked = true;
    if (widget is Text) {
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (text.contains('/Users/') ||
          text.contains('/private/') ||
          text.contains('/var/folders/')) {
        blocked = true;
      }
    }
    element.visitChildren(inspect);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(inspect);
  if (blocked) {
    throw StateError(
      'Screenshot blocked: dialog or private filesystem path is visible',
    );
  }
  final boundary = editorCaptureKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Editor capture boundary is unavailable');
  }
  log('capture rasterizing $path');
  final image = await boundary
      .toImage(pixelRatio: 2)
      .timeout(const Duration(seconds: 20));
  try {
    log('capture encoding $path');
    final bytes = (await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 20)))!;
    await File(path).writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
  log('capture saved $path');
}

IconButton? button(String key) {
  IconButton? found;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is IconButton && widget.key == ValueKey(key)) found = widget;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> waitUntil(
  bool Function() condition, {
  required String stage,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'Native preview timed out at $stage: ${jsonEncode(previewDiagnostics())}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Map<String, Object?> previewDiagnostics() {
  final messages = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Text &&
        element.findAncestorWidgetOfExactType<SnackBar>() != null) {
      messages.add(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  final control = button('canvas-preview-toggle');
  return {
    'lifecycle': SchedulerBinding.instance.lifecycleState?.name,
    'previewButtonFound': control != null,
    'previewEnabled': control?.onPressed != null,
    'previewTooltip': control?.tooltip,
    'previewIcon': '${control?.icon}',
    'snackbars': messages,
  };
}

bool playing() =>
    button('canvas-preview-toggle')?.icon is Icon &&
    (button('canvas-preview-toggle')!.icon as Icon).icon == Icons.pause;

Future<Map<String, Object?>> measurePreview(String name) async {
  final timings = <ui.FrameTiming>[];
  final startFrameNumber = ui.PlatformDispatcher.instance.frameData.frameNumber;
  void collect(List<ui.FrameTiming> values) => timings.addAll(values);
  SchedulerBinding.instance.addTimingsCallback(collect);
  final watch = Stopwatch()..start();
  final samples = <Map<String, int>>[];
  final frameSignal = canvasPainter()?.resolvedFrameListenable;
  if (frameSignal == null) {
    throw StateError('Production frame signal is unavailable');
  }
  void recordSample() {
    final frame = frameSignal.value;
    if (frame != null) {
      samples.add({
        'elapsedUs': watch.elapsedMicroseconds,
        'contentTimeUs': frame.time.microseconds,
      });
    }
  }

  frameSignal.addListener(recordSample);
  late int endFrameNumber;
  try {
    final control = button('canvas-preview-toggle');
    if (control?.onPressed == null) throw StateError('Preview is disabled');
    control!.onPressed!();
    await waitUntil(playing, stage: '$name-start-playing');
    await waitUntil(() => !playing(), stage: '$name-complete');
    watch.stop();
    endFrameNumber = ui.PlatformDispatcher.instance.frameData.frameNumber;
    // Engine timing batches may arrive after their presented frames.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    frameSignal.removeListener(recordSample);
  }
  final relevant = timings.where((f) {
    return f.frameNumber > startFrameNumber && f.frameNumber <= endFrameNumber;
  }).toList();
  if (relevant.isEmpty) {
    throw StateError('No real FrameTiming samples were recorded');
  }
  return {
    'name': name,
    'elapsedMs': watch.elapsedMilliseconds,
    'framesReported': relevant.length,
    'startFrameNumberExclusive': startFrameNumber,
    'endFrameNumberInclusive': endFrameNumber,
    'contentSamples': samples,
    'buildUs': stats(relevant.map((f) => f.buildDuration.inMicroseconds)),
    'rasterUs': stats(relevant.map((f) => f.rasterDuration.inMicroseconds)),
    'totalSpanUs': stats(relevant.map((f) => f.totalSpan.inMicroseconds)),
    'frames': [
      for (final f in relevant)
        {
          'frameNumber': f.frameNumber,
          'vsyncUs': f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          'buildUs': f.buildDuration.inMicroseconds,
          'rasterUs': f.rasterDuration.inMicroseconds,
          'totalSpanUs': f.totalSpan.inMicroseconds,
        },
    ],
    'viewport': viewport(),
  };
}

Map<String, Object?> stats(Iterable<int> values) {
  final sorted = values.toList()..sort();
  int percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  return {
    'count': sorted.length,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
    'max': sorted.last,
    'mean': sorted.fold<int>(0, (sum, v) => sum + v) / sorted.length,
  };
}

EditorCanvasPainter? canvasPainter() {
  EditorCanvasPainter? found;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is CustomPaint && widget.painter is EditorCanvasPainter) {
      found = widget.painter! as EditorCanvasPainter;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Map<String, Object?> viewport() {
  final view = ui.PlatformDispatcher.instance.views.first;
  final boxes = <Map<String, Object?>>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is CustomPaint && widget.painter is EditorCanvasPainter) {
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        boxes.add({
          'logicalWidth': box.size.width,
          'logicalHeight': box.size.height,
          'physicalWidth': box.size.width * view.devicePixelRatio,
          'physicalHeight': box.size.height * view.devicePixelRatio,
        });
      }
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return {
    'viewPhysicalWidth': view.physicalSize.width,
    'viewPhysicalHeight': view.physicalSize.height,
    'devicePixelRatio': view.devicePixelRatio,
    'displayRefreshRate': view.display.refreshRate,
    'canvasPaintRects': boxes,
  };
}

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> denseImage(ui.Size size) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Offset.zero & size,
    ui.Paint()..color = const ui.Color(0xff315b88),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  } finally {
    picture.dispose();
  }
}

List<DrawingStroke> denseStrokes() {
  final masks = List.generate(11, (index) {
    final left = (index % 4) * .25, top = (index ~/ 4) * .33;
    return [
      ui.Offset(left, top),
      ui.Offset((left + .25).clamp(0, 1), top),
      ui.Offset((left + .25).clamp(0, 1), (top + .33).clamp(0, 1)),
      ui.Offset(left, (top + .33).clamp(0, 1)),
    ];
  });
  return List.generate(2190, (index) {
    final scene = index % masks.length;
    final x = .02 + (index % 100) / 104, y = .02 + ((index ~/ 100) % 22) / 23;
    return DrawingStroke(
      id: 'dense-$index',
      name: 'Dense $index',
      sectionId: 'scene-$scene',
      points: [
        ui.Offset(x.clamp(0, .98), y.clamp(0, .98)),
        ui.Offset((x + .012).clamp(0, 1), (y + .006).clamp(0, 1)),
      ],
      clipPolygons: [masks[scene]],
    );
  });
}

Future<void> archiveScreenshots() async {
  log('screenshot-only: generating original diagram');
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const ink = Color(0xff19364c), accent = Color(0xff19bdda);
  void text(String value, Offset origin, double size, {Color color = ink}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'PlaypenSansArabic',
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, origin);
    painter.dispose();
  }

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(90, 100, 1260, 610),
      const Radius.circular(30),
    ),
    Paint()..color = const Color(0xfff6f9fc),
  );
  text('Ideas, drawn step by step.', const Offset(215, 135), 48);
  text(
    'A simple workflow for visual explanations',
    const Offset(280, 207),
    26,
    color: const Color(0xff557387),
  );
  const labels = ['Sketch', 'Animate', 'Share'];
  const captions = [
    'Start with an idea',
    'Make each stroke count',
    'Tell your story',
  ];
  for (var index = 0; index < 3; index++) {
    final x = 160.0 + index * 390;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 305, 330, 300),
      const Radius.circular(22),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      Offset(x + 165, 385),
      46,
      Paint()..color = accent.withValues(alpha: .15),
    );
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (index == 0) {
      canvas.drawLine(Offset(x + 138, 411), Offset(x + 191, 358), pen);
      canvas.drawLine(Offset(x + 131, 417), Offset(x + 145, 414), pen);
      canvas.drawLine(Offset(x + 187, 356), Offset(x + 197, 366), pen);
    } else if (index == 1) {
      final path = Path()
        ..moveTo(x + 127, 402)
        ..cubicTo(x + 145, 345, x + 178, 427, x + 201, 368);
      canvas.drawPath(path, pen);
      for (final p in [Offset(x + 127, 402), Offset(x + 201, 368)]) {
        canvas.drawCircle(p, 6, Paint()..color = accent);
      }
    } else {
      final triangle = Path()
        ..moveTo(x + 151, 360)
        ..lineTo(x + 187, 385)
        ..lineTo(x + 151, 410)
        ..close();
      canvas.drawPath(triangle, Paint()..color = ink);
    }
    text(labels[index], Offset(x + 83, 458), 36);
    text(
      captions[index],
      Offset(x + 25, 527),
      20,
      color: const Color(0xff557387),
    );
    if (index < 2) {
      final arrow = Path()
        ..moveTo(x + 348, 452)
        ..lineTo(x + 370, 452)
        ..moveTo(x + 362, 443)
        ..lineTo(x + 371, 452)
        ..lineTo(x + 362, 461);
      canvas.drawPath(
        arrow,
        pen
          ..color = accent
          ..strokeWidth = 4,
      );
    }
  }
  final picture = recorder.endRecording();
  final source = await picture.toImage(1440, 810);
  picture.dispose();
  final bytes = (await source.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  final sourceFile = File('${output.path}/archive-diagram.png');
  await sourceFile.writeAsBytes(bytes);
  log('screenshot-only: planning drawing paths');
  final strokes = const RegionDrawingPlanner(quickPaint: true)
      .build(bytes)
      .ordered(ImageDrawingOrder.regionFirst)
      .map((item) => item.stroke)
      .toList();
  final project = HandDrawProject(
    canvasWidth: 1920,
    canvasHeight: 1080,
    durationSeconds: 12,
    drawingDurationSeconds: 12,
    startDelaySeconds: 0,
    endHoldSeconds: 0,
    drawingImageBase64: base64Encode(bytes),
    imageAnimationEffect: 'drawPaint',
    strokes: strokes,
  );
  final initial = testEditorState(project: project, drawingImage: source);
  final document = initial.document.copyWith(
    title: 'Ideas, drawn step by step',
    assets: [
      for (final asset in initial.document.assets)
        asset.copyWith(
          contentHash: 'sha256:${sha256.convert(bytes)}',
          externalLocator: ExternalAssetLocator(pathHint: sourceFile.path),
        ),
    ],
  );
  final editor = EditorCubit(
    initialState: initial.copyWith(
      documentState: initial.documentState.replace(document),
    ),
    handLibraryRepository: MemoryHandLibraryRepository(),
  );
  try {
    await editor.initializeHandLibrary();
    final snapshot = await editor.acquireRenderSnapshot(
      kind: StagedAssetReferenceKind.preview,
    );
    await snapshot.release();
    activeEditor.value = editor;
    await nextFrame();
    await waitUntil(
      () => button('canvas-preview-toggle')?.onPressed != null,
      stage: 'screenshot-only-mount',
    );
    // Idle editor shows the complete original illustration without waiting for an export.
    await captureEditor('${output.path}/editor-overview.png');
    log('screenshot-only: starting production playback');
    button('canvas-preview-toggle')!.onPressed!();
    await waitUntil(playing, stage: 'screenshot-only-start');
    await Future<void>.delayed(const Duration(seconds: 7));
    await pauseForScreenshot();
    await captureEditor('${output.path}/drawing-preview.png');
    report['screenshots'] = {
      'overview': '${output.path}/editor-overview.png',
      'preview': '${output.path}/drawing-preview.png',
      'source': sourceFile.path,
      'sourceSha256': sha256.convert(bytes).toString(),
      'viewport': viewport(),
      'fixture': 'Original diagram generated locally with Canvas/TextPainter',
      'notPerformanceMeasurement': true,
    };
    button('canvas-preview-stop')?.onPressed?.call();
  } finally {
    activeEditor.value = null;
    await nextFrame();
    final hand = editor.state.handImage;
    await editor.close();
    hand?.dispose();
    source.dispose();
  }
}
