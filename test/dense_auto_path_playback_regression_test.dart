import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

void main() {
  test('a 6634-path project starts playback without a multi-second stall', () {
    final strokes = _denseStrokes(6634);

    final watch = Stopwatch()..start();
    final snapshot = buildTimelineSnapshot(
      strokes: strokes,
      artworkRect: const Rect.fromLTWH(0, 0, 712, 400),
      timingRect: const Rect.fromLTWH(0, 0, 1920, 1080),
      progress: 0.92,
      durationSeconds: 6,
      drawingDurationSeconds: 6,
    );
    watch.stop();

    expect(snapshot.revealedPaths.length, greaterThan(6000));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: 'First-frame geometry must stay lazy for dense Auto Path scenes.',
    );
  });

  test('8062-path playback reuses one stable reveal plan across frames', () {
    final strokes = _denseStrokes(8062);
    const artworkRect = Rect.fromLTWH(0, 0, 712, 400);
    const timingRect = Rect.fromLTWH(0, 0, 1920, 1080);
    final first = buildTimelineSnapshot(
      strokes: strokes,
      artworkRect: artworkRect,
      timingRect: timingRect,
      progress: 0.01,
      durationSeconds: 6,
      drawingDurationSeconds: 6,
    );
    final backing = first.stableRevealSequence!.paths;
    final backingClips = first.sectionClips;

    final watch = Stopwatch()..start();
    for (var frame = 1; frame < 180; frame++) {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        timingRect: timingRect,
        progress: frame / 180,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );
      expect(identical(snapshot.stableRevealSequence!.paths, backing), isTrue);
      expect(identical(snapshot.sectionClips, backingClips), isTrue);
      expect(
        snapshot.revealedPaths.length,
        snapshot.stableRevealSequence!.visibleCount +
            (snapshot.stableRevealSequence!.activePath == null ? 0 : 1),
      );
    }
    watch.stop();

    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason:
          'Playback frames must binary-search and reuse completed paths rather '
          'than scan and allocate the elapsed 8062-path prefix.',
    );
  });

  test('cold first compositor frame stays bounded for 8062 paths', () async {
    final strokes = _denseStrokes(8062);
    const artworkRect = Rect.fromLTWH(0, 0, 712, 400);
    final source = await _solidImage(712, 400, const Color(0xFF2F80ED));
    try {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        progress: 0.002,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );
      final watch = Stopwatch()..start();
      final recorder = PictureRecorder();
      drawRevealedArtwork(
        canvas: Canvas(recorder),
        image: source,
        artworkRect: artworkRect,
        snapshot: snapshot,
        defaultRevealWidth: 12,
      );
      final rendered = await recorder.endRecording().toImage(712, 400);
      rendered.dispose();
      watch.stop();

      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason:
            'The first paint must build only visible brush chunks instead of '
            'recording all 8062 paths before playback can start.',
      );
    } finally {
      source.dispose();
    }
  });

  test(
    'idle prewarm keeps a cold 90% seek bounded and pixel-identical',
    () async {
      addTearDown(debugResetRevealCompositorCaches);
      final strokes = _denseStrokes(8062);
      const artworkRect = Rect.fromLTWH(0, 0, 712, 400);
      final source = await _solidImage(712, 400, const Color(0xFF2F80ED));
      try {
        final snapshot = buildTimelineSnapshot(
          strokes: strokes,
          artworkRect: artworkRect,
          progress: 0.9,
          durationSeconds: 6,
          drawingDurationSeconds: 6,
        );
        final idleSnapshot = buildTimelineSnapshot(
          strokes: strokes,
          artworkRect: artworkRect,
          progress: 0.999999,
          durationSeconds: 6,
          drawingDurationSeconds: 6,
        );

        debugResetRevealCompositorCaches();
        final coldBytes = await _renderReveal(
          source: source,
          snapshot: snapshot,
          artworkRect: artworkRect,
        );

        debugResetRevealCompositorCaches();
        final prewarmWatch = Stopwatch()..start();
        await prewarmRevealedArtwork(
          artworkRect: artworkRect,
          snapshot: idleSnapshot,
          defaultRevealWidth: 12,
        );
        prewarmWatch.stop();
        final buildsBeforeSeek = debugRevealBrushChunkBuildCount;

        final seekWatch = Stopwatch()..start();
        final prewarmedBytes = await _renderReveal(
          source: source,
          snapshot: snapshot,
          artworkRect: artworkRect,
        );
        seekWatch.stop();
        final seekChunkBuilds =
            debugRevealBrushChunkBuildCount - buildsBeforeSeek;

        expect(prewarmedBytes, orderedEquals(coldBytes));
        expect(
          seekChunkBuilds,
          lessThanOrEqualTo(2),
          reason:
              'A 90% seek may build only bounded active-batch tails; '
              'completed chunks must come from the idle prewarm cache.',
        );
        expect(
          seekWatch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason:
              'The first dense seek after idle prewarm must not combine the '
              'elapsed 8062-path prefix in one frame.',
        );
        expect(
          prewarmWatch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'Prewarm must finish promptly while yielding every 4ms.',
        );
      } finally {
        source.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'evicting an in-flight prewarm cannot resurrect an orphan cache entry',
    () async {
      addTearDown(debugResetRevealCompositorCaches);
      debugResetRevealCompositorCaches();
      final strokes = _denseStrokes(8062);
      const artworkRect = Rect.fromLTWH(0, 0, 712, 400);
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        progress: 0.999999,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );

      final prewarm = prewarmRevealedArtwork(
        artworkRect: artworkRect,
        snapshot: snapshot,
        defaultRevealWidth: 12,
      );
      for (
        var attempt = 0;
        attempt < 200 && debugRevealStableCacheEntryCount == 0;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        debugRevealStableCacheEntryCount,
        1,
        reason: 'The test must evict after compilation, during chunk prewarm.',
      );

      debugResetRevealCompositorCaches();
      await prewarm;

      expect(debugRevealStableCacheEntryCount, 0);
      expect(
        debugRevealPrewarmedKeyCount,
        0,
        reason:
            'Disposed work must not repopulate Pictures/Paths or mark an '
            'evicted key as warm.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a resize supersedes the previous editor prewarm generation', () async {
    final coordinator = EditorRevealPrewarmCoordinator();
    final gate = Completer<void>();
    var oldGenerationCancelled = false;
    var latestGenerationCancelled = true;

    final oldSize = coordinator.schedule('712x400', (isCancelled) async {
      await gate.future;
      oldGenerationCancelled = isCancelled();
    });
    final latestSize = coordinator.schedule('640x360', (isCancelled) async {
      await gate.future;
      latestGenerationCancelled = isCancelled();
    });
    gate.complete();
    await Future.wait([oldSize, latestSize]);

    expect(oldGenerationCancelled, isTrue);
    expect(latestGenerationCancelled, isFalse);
  });

  test(
    'stable reveal compositor is pixel-identical to the legacy path',
    () async {
      final strokes = _denseStrokes(320);
      const artworkRect = Rect.fromLTWH(0, 0, 320, 180);
      final optimized = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        progress: 0.73,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );
      final legacy = TimelineSnapshot(
        revealedPaths: optimized.revealedPaths.toList(growable: false),
        handPosition: optimized.handPosition,
        handAngle: optimized.handAngle,
        handVisible: optimized.handVisible,
        sectionClips: optimized.sectionClips,
      );
      final source = await _solidImage(320, 180, const Color(0xFF2F80ED));
      try {
        final optimizedBytes = await _renderReveal(
          source: source,
          snapshot: optimized,
          artworkRect: artworkRect,
        );
        final legacyBytes = await _renderReveal(
          source: source,
          snapshot: legacy,
          artworkRect: artworkRect,
        );
        expect(optimizedBytes, orderedEquals(legacyBytes));
      } finally {
        source.dispose();
      }
    },
  );

  test(
    'stable layered reveal is pixel-identical to the legacy compositor',
    () async {
      final strokes = _denseStrokes(320, preciseSceneMask: true);
      const artworkRect = Rect.fromLTWH(0, 0, 320, 180);
      final optimized = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        progress: 0.73,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );
      final legacy = TimelineSnapshot(
        revealedPaths: optimized.revealedPaths.toList(growable: false),
        handPosition: optimized.handPosition,
        handAngle: optimized.handAngle,
        handVisible: optimized.handVisible,
        sectionClips: optimized.sectionClips,
      );
      final complete = await _solidImage(320, 180, const Color(0xFF2F80ED));
      final base = await _solidImage(320, 180, const Color(0xFFE58B2A));
      try {
        final optimizedBytes = await _renderReveal(
          source: complete,
          revealBase: base,
          snapshot: optimized,
          artworkRect: artworkRect,
        );
        final legacyBytes = await _renderReveal(
          source: complete,
          revealBase: base,
          snapshot: legacy,
          artworkRect: artworkRect,
        );
        expect(optimizedBytes, orderedEquals(legacyBytes));
      } finally {
        complete.dispose();
        base.dispose();
      }
    },
  );

  test('warm compositor playback stays bounded for 8062 paths', () async {
    final strokes = _denseStrokes(8062);
    const artworkRect = Rect.fromLTWH(0, 0, 712, 400);
    final source = await _solidImage(712, 400, const Color(0xFF2F80ED));
    try {
      final warm = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artworkRect,
        progress: 0.45,
        durationSeconds: 6,
        drawingDurationSeconds: 6,
      );
      final warmRecorder = PictureRecorder();
      drawRevealedArtwork(
        canvas: Canvas(warmRecorder),
        image: source,
        artworkRect: artworkRect,
        snapshot: warm,
        defaultRevealWidth: 12,
      );
      warmRecorder.endRecording().dispose();

      final watch = Stopwatch()..start();
      for (var frame = 0; frame < 90; frame++) {
        final snapshot = buildTimelineSnapshot(
          strokes: strokes,
          artworkRect: artworkRect,
          progress: 0.45 + frame / 200,
          durationSeconds: 6,
          drawingDurationSeconds: 6,
        );
        final recorder = PictureRecorder();
        drawRevealedArtwork(
          canvas: Canvas(recorder),
          image: source,
          artworkRect: artworkRect,
          snapshot: snapshot,
          defaultRevealWidth: 12,
        );
        recorder.endRecording().dispose();
      }
      watch.stop();
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason:
            'Warm playback must reuse compiled brush batches and effective '
            'clips rather than regroup all 8062 paths every frame.',
      );
    } finally {
      source.dispose();
    }
  });

  test(
    '8062-path layered playback rasterizes full frames without a stall',
    () async {
      final strokes = _denseStrokes(8062, preciseSceneMask: true);
      const artworkRect = Rect.fromLTWH(0, 0, 1920, 1080);
      final complete = await _solidImage(1920, 1080, const Color(0xFF2F80ED));
      final base = await _solidImage(1920, 1080, const Color(0xFFE58B2A));
      try {
        Future<void> render(double progress) async {
          final snapshot = buildTimelineSnapshot(
            strokes: strokes,
            artworkRect: artworkRect,
            progress: progress,
            durationSeconds: 6,
            drawingDurationSeconds: 6,
          );
          final recorder = PictureRecorder();
          drawRevealedArtwork(
            canvas: Canvas(recorder),
            image: complete,
            revealBaseImage: base,
            artworkRect: artworkRect,
            snapshot: snapshot,
            defaultRevealWidth: 12,
          );
          final rendered = await recorder.endRecording().toImage(1920, 1080);
          rendered.dispose();
        }

        await render(0.45);
        final watch = Stopwatch()..start();
        for (var frame = 0; frame < 6; frame++) {
          await render(0.46 + frame / 100);
        }
        watch.stop();
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 6)),
          reason:
              'The benchmark must include real 1080p rasterization, not only '
              'Picture recording.',
        );
      } finally {
        complete.dispose();
        base.dispose();
      }
    },
  );
}

List<DrawingStroke> _denseStrokes(int count, {bool preciseSceneMask = false}) =>
    List.generate(count, (index) {
      final columns = 100;
      final rows = (count / columns).ceil();
      final x = (index % columns) / columns;
      final y = (index ~/ columns) / rows;
      final start = Offset(x, y);
      final end = Offset((x + 0.006).clamp(0, 1), (y + 0.004).clamp(0, 1));
      final sectionIndex = index ~/ 190;
      return DrawingStroke(
        id: 'dense-$index',
        name: 'Dense $index',
        points: [start, end],
        geometry: StrokePathGeometry(
          start: start,
          segments: [StrokeLineSegment(end: end)],
        ),
        sectionId: 'section-$sectionIndex',
        clipBounds: Rect.fromLTWH(0, sectionIndex / 43, 1, 1 / 43),
        clipPolygons: preciseSceneMask
            ? const [
                [
                  Offset(0.02, 0.02),
                  Offset(0.98, 0.02),
                  Offset(0.98, 0.98),
                  Offset(0.02, 0.98),
                ],
              ]
            : const [],
        exclusionBounds: index.isEven
            ? const [Rect.fromLTWH(0.92, 0, 0.08, 0.05)]
            : const [],
      );
    });

Future<Image> _solidImage(int width, int height, Color color) async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(width, height);
}

Future<List<int>> _renderReveal({
  required Image source,
  Image? revealBase,
  required TimelineSnapshot snapshot,
  required Rect artworkRect,
}) async {
  final recorder = PictureRecorder();
  drawRevealedArtwork(
    canvas: Canvas(recorder),
    image: source,
    revealBaseImage: revealBase,
    artworkRect: artworkRect,
    snapshot: snapshot,
    defaultRevealWidth: 12,
  );
  final image = await recorder.endRecording().toImage(
    artworkRect.width.round(),
    artworkRect.height.round(),
  );
  try {
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
