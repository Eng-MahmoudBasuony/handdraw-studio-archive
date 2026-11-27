import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

const _runBaseline = bool.fromEnvironment('HANDDRAW_RUN_BASELINE');
final _clockFrequency = Stopwatch().frequency;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'records timeline, renderer, and process-memory baseline',
    () async {
      const warmUpIterations = 30;
      const timelineMeasurements = 300;
      const snapshotMeasurements = 180;

      for (final sectionCount in [40, 200, 1000]) {
        final project = _project(sectionCount, width: 1280, height: 720);
        for (var index = 0; index < warmUpIterations; index++) {
          resolveProjectTimeline(project);
          _snapshot(project, index / warmUpIterations);
        }
        final resolutionSamples = _measure(
          timelineMeasurements,
          () => resolveProjectTimeline(project),
        );
        final snapshotSamples = _measure(
          snapshotMeasurements,
          () => _snapshot(project, 0.47),
        );
        _printSamples(
          label: 'timeline_resolution',
          scale: '$sectionCount sections',
          warmUp: warmUpIterations,
          samples: resolutionSamples,
        );
        _printSamples(
          label: 'snapshot_generation',
          scale: '$sectionCount sections',
          warmUp: warmUpIterations,
          samples: snapshotSamples,
        );
      }

      for (final size in const [(1280, 720), (1920, 1080), (3840, 2160)]) {
        await _renderResolution(size.$1, size.$2);
      }
      // Mirrors the dense Auto Path failure mode that previously crossed the
      // fixed 512-entry geometry cache and made Preview appear frozen.
      await _renderResolution(1920, 1080, sectionCount: 600, cycles: 1);
    },
    skip: _runBaseline
        ? false
        : 'Opt-in: flutter test --dart-define=HANDDRAW_RUN_BASELINE=true test/performance_baseline_test.dart',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

List<int> _measure(int count, void Function() operation) {
  return List.generate(count, (_) {
    final watch = Stopwatch()..start();
    operation();
    watch.stop();
    return watch.elapsedTicks;
  }, growable: false);
}

void _printSamples({
  required String label,
  required String scale,
  required int warmUp,
  required List<int> samples,
}) {
  final sorted = [...samples]..sort();
  final total = samples.fold<int>(0, (sum, value) => sum + value);
  // Keep sub-microsecond measurements instead of truncating each sample to 0.
  String micros(num ticks) =>
      (ticks * 1e6 / _clockFrequency).toStringAsFixed(3);
  // Benchmark output is intentionally machine-greppable for future comparison.
  // ignore: avoid_print
  print(
    'BASELINE mode=debug_jit operation=$label scale="$scale" '
    'warmup=$warmUp samples=${samples.length} clock_hz=$_clockFrequency '
    'mean_us=${micros(total / samples.length)} '
    'p50_us=${micros(_percentile(sorted, 0.50))} '
    'p95_us=${micros(_percentile(sorted, 0.95))}',
  );
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];

Future<void> _renderResolution(
  int width,
  int height, {
  int sectionCount = 40,
  int cycles = 2,
}) async {
  final source = await _sourceImage(width, height);
  final project = _project(sectionCount, width: width, height: height);
  const fallbackProgressPoints = [
    0.0,
    0.08,
    0.18,
    0.32,
    0.47,
    0.58,
    0.72,
    0.86,
    0.96,
    1.0,
  ];
  final progressPoints = _benchmarkProgressPoints(
    project,
    fallbackProgressPoints,
  );
  final renderer = const FrameRenderer();

  final warmUp = await renderer.render(
    project: project,
    drawing: source,
    hand: null,
    progress: 0.47,
  );
  warmUp.dispose();
  final memoryAfterWarmUp = ProcessInfo.currentRss;
  final samples = <int>[];
  final phases = <TimelinePhase>{};
  for (var cycle = 0; cycle < cycles; cycle++) {
    for (final progress in progressPoints) {
      phases.add(_snapshot(project, progress).phase);
      final watch = Stopwatch()..start();
      final frame = await renderer.render(
        project: project,
        drawing: source,
        hand: null,
        progress: progress,
      );
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
      frame.dispose();
    }
  }
  final memoryAfterCycles = ProcessInfo.currentRss;
  source.dispose();
  final sorted = [...samples]..sort();
  final total = samples.fold<int>(0, (sum, value) => sum + value);
  // ignore: avoid_print
  print(
    'BASELINE mode=debug_jit operation=canvas_render '
    'scale="${width}x$height paths=$sectionCount" '
    'warmup_frames=1 cycles=$cycles samples=${samples.length} '
    'mean_ms=${total / samples.length / 1000} '
    'p50_ms=${_percentile(sorted, 0.50) / 1000} '
    'p95_ms=${_percentile(sorted, 0.95) / 1000} '
    'rss_after_warmup=$memoryAfterWarmUp rss_after_cycles=$memoryAfterCycles '
    'rss_delta=${memoryAfterCycles - memoryAfterWarmUp} '
    'disposed_each_frame=true png_encoding=false '
    'phases=${phases.map((phase) => phase.name).join(',')}',
  );
}

List<double> _benchmarkProgressPoints(
  HandDrawProject project,
  List<double> fallback,
) {
  const desiredPhases = {
    TimelinePhase.startDelay,
    TimelinePhase.drawing,
    TimelinePhase.travel,
    TimelinePhase.pauseBefore,
    TimelinePhase.pauseAfter,
    TimelinePhase.endHold,
  };
  final selected = <TimelinePhase, double>{};
  for (var step = 0; step <= 4000; step++) {
    final progress = step / 4000;
    final phase = _snapshot(project, progress).phase;
    if (desiredPhases.contains(phase)) {
      selected.putIfAbsent(phase, () => progress);
    }
  }
  final result = <double>{...selected.values};
  for (final progress in fallback) {
    if (result.length >= 10) break;
    result.add(progress);
  }
  return (result.toList()..sort()).take(10).toList(growable: false);
}

TimelineSnapshot _snapshot(HandDrawProject project, double progress) =>
    buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: ui.Rect.fromLTWH(
        0,
        0,
        project.canvasWidth.toDouble(),
        project.canvasHeight.toDouble(),
      ),
      timingRect: ui.Rect.fromLTWH(
        0,
        0,
        project.canvasWidth.toDouble(),
        project.canvasHeight.toDouble(),
      ),
      progress: progress,
      durationSeconds: project.durationSeconds,
      drawingDurationSeconds: project.drawingDurationSeconds,
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
    );

HandDrawProject _project(
  int sectionCount, {
  required int width,
  required int height,
}) {
  final strokes = List.generate(sectionCount, (index) {
    final row = index / sectionCount;
    final x = 0.05 + (index % 10) * 0.085;
    return DrawingStroke(
      id: 'stroke-$index',
      name: 'Stroke $index',
      sectionId: 'section-$index',
      points: [
        ui.Offset(x, 0.03 + row * 0.9),
        ui.Offset((x + 0.04).clamp(0, 1), 0.035 + row * 0.9),
      ],
    );
  });
  return HandDrawProject(
    canvasWidth: width,
    canvasHeight: height,
    durationSeconds: 20,
    drawingDurationSeconds: 17,
    startDelaySeconds: 1,
    endHoldSeconds: 2,
    strokes: strokes,
    sectionTimings: {
      for (var index = 0; index < sectionCount; index++)
        'section:section-$index': SectionTiming(
          pauseAfterSeconds: index % 8 == 0 ? 0.5 : 0,
          transitionAfterSeconds: index % 5 == 0 ? 0.05 : 0,
        ),
    },
  );
}

Future<ui.Image> _sourceImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
