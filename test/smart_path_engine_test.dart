import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

class _FakeTextDetector implements TextLayoutDetector {
  const _FakeTextDetector(this.regions);

  final List<SmartTextRegion> regions;

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async => regions;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('graph planner visits every branch edge deterministically', () {
    const width = 5;
    const height = 5;
    final skeleton = Uint8List(width * height);
    for (var x = 0; x < width; x++) {
      skeleton[2 * width + x] = 1;
    }
    skeleton[width + 2] = 1;
    skeleton[2] = 1;

    const planner = SkeletonGraphPlanner();
    final first = planner.buildTrails(skeleton, width, height);
    final second = planner.buildTrails(skeleton, width, height);

    expect(first, equals(second));
    expect(
      first.fold<int>(0, (edgeCount, trail) => edgeCount + trail.length - 1),
      6,
    );
  });

  test('detects text center paths and separate unclaimed artwork', () async {
    final image = await _fixtureImage();
    final engine = SmartPathEngine(
      textDetector: const _FakeTextDetector([
        SmartTextRegion(
          text: 'HI',
          bounds: ui.Rect.fromLTWH(0.05, 0.12, 0.48, 0.42),
          confidence: 0.98,
        ),
      ]),
    );

    final result = await engine.analyze(
      image: image,
      encodedImage: Uint8List.fromList([1, 2, 3]),
    );

    final text = result.sections.where(
      (section) => section.kind == SmartSectionKind.text,
    );
    final artwork = result.sections.where(
      (section) => section.kind == SmartSectionKind.shape,
    );
    expect(text, hasLength(1));
    expect(text.single.label, 'HI');
    expect(text.single.paths, isNotEmpty);
    expect(artwork, isNotEmpty);
    for (final section in result.sections) {
      expect(section.bounds.left, inInclusiveRange(0, 1));
      expect(section.bounds.right, inInclusiveRange(0, 1));
      expect(section.recommendedRevealWidth, greaterThan(0));
      for (final path in section.paths) {
        expect(path.points.length, greaterThanOrEqualTo(2));
        for (final point in path.points) {
          expect(point.dx, inInclusiveRange(0, 1));
          expect(point.dy, inInclusiveRange(0, 1));
        }
      }
    }
    image.dispose();
  });

  test('maps worker output directly into requested artwork bounds', () async {
    final image = await _fixtureImage();
    final engine = SmartPathEngine(textDetector: const _FakeTextDetector([]));
    final local = await engine.analyze(
      image: image,
      encodedImage: Uint8List(0),
    );
    const output = ui.Rect.fromLTWH(0.2, 0.3, 0.45, 0.25);
    final mapped = await engine.analyze(
      image: image,
      encodedImage: Uint8List(0),
      coordinateBounds: output,
    );

    expect(mapped.sections, hasLength(local.sections.length));
    for (
      var sectionIndex = 0;
      sectionIndex < local.sections.length;
      sectionIndex++
    ) {
      final source = local.sections[sectionIndex];
      final target = mapped.sections[sectionIndex];
      expect(
        target.bounds,
        ui.Rect.fromLTRB(
          output.left + source.bounds.left * output.width,
          output.top + source.bounds.top * output.height,
          output.left + source.bounds.right * output.width,
          output.top + source.bounds.bottom * output.height,
        ),
      );
      expect(
        target.recommendedRevealWidth,
        closeTo(source.recommendedRevealWidth * output.height, 1e-9),
      );
      for (var pathIndex = 0; pathIndex < source.paths.length; pathIndex++) {
        final sourcePoints = source.paths[pathIndex].points;
        final targetPoints = target.paths[pathIndex].points;
        expect(targetPoints, hasLength(sourcePoints.length));
        for (
          var pointIndex = 0;
          pointIndex < sourcePoints.length;
          pointIndex++
        ) {
          expect(
            targetPoints[pointIndex],
            ui.Offset(
              output.left + sourcePoints[pointIndex].dx * output.width,
              output.top + sourcePoints[pointIndex].dy * output.height,
            ),
          );
        }
      }
    }
    image.dispose();
  });

  test('reports monotonic real analysis stages while tracing', () async {
    final image = await _fixtureImage();
    final updates = <SmartPathProgress>[];

    await SmartPathEngine(textDetector: const _FakeTextDetector([])).analyze(
      image: image,
      encodedImage: Uint8List(0),
      onProgress: updates.add,
    );

    expect(updates, isNotEmpty);
    expect(updates.first.stage, SmartPathProgressStage.recognizingText);
    expect(
      updates.map((update) => update.stage),
      containsAll([
        SmartPathProgressStage.readingPixels,
        SmartPathProgressStage.preparingRaster,
        SmartPathProgressStage.findingShapes,
        SmartPathProgressStage.tracingShapes,
        SmartPathProgressStage.finalizing,
      ]),
    );
    for (var index = 1; index < updates.length; index++) {
      expect(
        updates[index].fraction,
        greaterThanOrEqualTo(updates[index - 1].fraction),
      );
    }
    expect(updates.last.fraction, 0.99);
    image.dispose();
  });

  test('cancellation terminates an in-flight raster worker', () async {
    final image = await _largeCancellationFixtureImage();
    final cancellation = SmartPathCancellationToken();
    var cancelledFromWorkerProgress = false;

    final analysis = SmartPathEngine(textDetector: const _FakeTextDetector([]))
        .analyze(
          image: image,
          encodedImage: Uint8List(0),
          cancellationToken: cancellation,
          onProgress: (update) {
            if (!cancelledFromWorkerProgress &&
                update.stage == SmartPathProgressStage.preparingRaster &&
                update.fraction > 0.20) {
              cancelledFromWorkerProgress = true;
              cancellation.cancel();
            }
          },
        );

    await expectLater(
      analysis,
      throwsA(isA<SmartPathCancelledException>()),
    ).timeout(const Duration(seconds: 5));
    expect(cancelledFromWorkerProgress, isTrue);
    image.dispose();
  });

  test('cancellation also stops responsive result materialization', () async {
    final image = await _fixtureImage();
    final cancellation = SmartPathCancellationToken();
    addTearDown(image.dispose);

    final analysis = SmartPathEngine(textDetector: const _FakeTextDetector([]))
        .analyze(
          image: image,
          encodedImage: Uint8List(0),
          cancellationToken: cancellation,
          onProgress: (update) {
            if (update.stage == SmartPathProgressStage.finalizing &&
                update.fraction >= 0.98) {
              cancellation.cancel();
            }
          },
        );

    await expectLater(analysis, throwsA(isA<SmartPathCancelledException>()));
  });

  test('continues with shape analysis when OCR is unavailable', () async {
    final image = await _fixtureImage();
    final result = await SmartPathEngine(
      textDetector: _ThrowingDetector(),
    ).analyze(image: image, encodedImage: Uint8List(0));

    expect(result.sections, isNotEmpty);
    expect(
      result.sections.every(
        (section) => section.kind == SmartSectionKind.shape,
      ),
      isTrue,
    );
    expect(result.warnings, isNotEmpty);
    image.dispose();
  });

  test(
    'frame experiment excludes only a high-confidence canvas frame',
    () async {
      final image = await _frameFixtureImage();
      final enabled = await SmartPathEngine(
        textDetector: const _FakeTextDetector([]),
        processingOptions: const SmartPathProcessingOptions(
          suspectedFrameDetection: true,
        ),
      ).analyze(image: image, encodedImage: Uint8List(0));
      final baseline = await SmartPathEngine(
        textDetector: const _FakeTextDetector([]),
        processingOptions: const SmartPathProcessingOptions(),
      ).analyze(image: image, encodedImage: Uint8List(0));

      final candidates = enabled.sections.where(
        (section) => section.isSuspectedFrame,
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.mode, SmartSectionMode.ignore);
      expect(candidates.single.artifactConfidence, greaterThanOrEqualTo(0.96));
      expect(enabled.processing.suspectedFrameDetection, isTrue);
      expect(
        baseline.sections.any((section) => section.isSuspectedFrame),
        isFalse,
      );
      expect(
        baseline.sections.every(
          (section) => section.mode == SmartSectionMode.handDraw,
        ),
        isTrue,
      );
      image.dispose();
    },
  );

  test(
    'keeps translucent artwork and sizes the reveal for solid fills',
    () async {
      final image = await _translucentFixtureImage();
      final result = await SmartPathEngine(
        textDetector: const _FakeTextDetector([]),
      ).analyze(image: image, encodedImage: Uint8List(0));

      expect(result.sections, isNotEmpty);
      final section = result.sections.first;
      expect(section.kind, SmartSectionKind.shape);
      expect(section.paths, isNotEmpty);
      expect(section.recommendedRevealWidth, greaterThan(0.20));
      final entersFilledCenter = section.paths.any(
        (path) => path.points.any(
          (point) =>
              point.dx > 0.33 &&
              point.dx < 0.67 &&
              point.dy > 0.38 &&
              point.dy < 0.62,
        ),
      );
      expect(entersFilledCenter, isFalse);

      final clip = section.bounds
          .inflate(section.recommendedRevealWidth * 0.8)
          .intersect(const ui.Rect.fromLTWH(0, 0, 1, 1));
      final project = HandDrawProject(
        canvasWidth: 240,
        canvasHeight: 120,
        durationSeconds: 1,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        strokes: [
          for (var index = 0; index < section.paths.length; index++)
            DrawingStroke(
              id: 'auto-$index',
              name: section.label,
              points: section.paths[index].points,
              clipBounds: clip,
              revealWidth: section.recommendedRevealWidth * 120,
            ),
        ],
      );
      final frame = await const FrameRenderer().render(
        project: project,
        drawing: image,
        hand: null,
        progress: 1,
      );
      final sourceRgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final outputRgba = (await frame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var expectedPixels = 0;
      var missingPixels = 0;
      for (var offset = 3; offset < sourceRgba.length; offset += 4) {
        if (sourceRgba[offset] < 8) continue;
        expectedPixels++;
        if (outputRgba[offset] == 0) missingPixels++;
      }
      expect(expectedPixels, greaterThan(1000));
      expect(missingPixels / expectedPixels, lessThan(0.02));
      frame.dispose();
      image.dispose();
    },
  );

  test('text paths ignore a translucent fill behind opaque glyphs', () async {
    final image = await _translucentTextFixtureImage();
    final result = await SmartPathEngine(
      textDetector: const _FakeTextDetector([
        SmartTextRegion(
          text: 'X',
          bounds: ui.Rect.fromLTWH(0.20, 0.20, 0.60, 0.60),
          confidence: 0.99,
        ),
      ]),
    ).analyze(image: image, encodedImage: Uint8List(0));

    final text = result.sections.singleWhere(
      (section) => section.kind == SmartSectionKind.text,
    );
    expect(text.paths, isNotEmpty);
    expect(text.recommendedRevealWidth, lessThan(0.20));

    final rgba = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    for (final path in text.paths) {
      for (final point in path.points) {
        final x = (point.dx * image.width).floor().clamp(0, image.width - 1);
        final y = (point.dy * image.height).floor().clamp(0, image.height - 1);
        expect(
          rgba[(y * image.width + x) * 4 + 3],
          greaterThanOrEqualTo(160),
          reason: 'The text pen path must stay on the opaque glyph.',
        );
      }
    }
    image.dispose();
  });

  test('fixed quality benchmark preserves a one-pixel 4K connector', () async {
    final manifest =
        jsonDecode(
              File(
                'test/fixtures/path_quality_benchmark.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest['schemaVersion'], 1);
    final benchmark =
        (manifest['cases'] as Map<String, dynamic>)['onePixel4kConnector']
            as Map<String, dynamic>;
    final image = await _thinHighResolutionFixtureImage();
    expect(image.width, benchmark['width']);
    expect(image.height, benchmark['height']);
    final result = await SmartPathEngine(
      textDetector: const _FakeTextDetector([]),
    ).analyze(image: image, encodedImage: Uint8List(0));

    final points = result.sections
        .expand((section) => section.paths)
        .expand((path) => path.points)
        .toList(growable: false);
    expect(points, isNotEmpty);
    expect(
      points.map((point) => point.dx).reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(benchmark['minimumLeftCoverage'] as double),
    );
    expect(
      points.map((point) => point.dx).reduce((a, b) => a > b ? a : b),
      greaterThanOrEqualTo(benchmark['minimumRightCoverage'] as double),
    );
    expect(
      points
          .map((point) => (point.dy - 0.5).abs())
          .reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(benchmark['maximumVerticalError'] as double),
    );
    image.dispose();
  });
}

class _ThrowingDetector implements TextLayoutDetector {
  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) {
    throw UnsupportedError('OCR unavailable');
  }
}

Future<ui.Image> _fixtureImage() async {
  const width = 240;
  const height = 120;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..color = const ui.Color(0xFF151515)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 10
    ..strokeCap = ui.StrokeCap.round;

  // Text-like H and I inside the OCR box.
  canvas.drawLine(const ui.Offset(25, 22), const ui.Offset(25, 58), paint);
  canvas.drawLine(const ui.Offset(25, 40), const ui.Offset(55, 40), paint);
  canvas.drawLine(const ui.Offset(55, 22), const ui.Offset(55, 58), paint);
  canvas.drawLine(const ui.Offset(88, 22), const ui.Offset(88, 58), paint);

  // A separate artwork shape outside the OCR box.
  canvas.drawCircle(const ui.Offset(180, 78), 24, paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _frameFixtureImage() async {
  const width = 240;
  const height = 120;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..color = const ui.Color(0xFF151515)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 3;
  canvas.drawRect(const ui.Rect.fromLTRB(3, 3, 237, 117), paint);
  canvas.drawCircle(const ui.Offset(120, 60), 12, paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _translucentFixtureImage() async {
  const width = 240;
  const height = 120;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(60, 35, 120, 50),
      const ui.Radius.circular(10),
    ),
    ui.Paint()..color = const ui.Color.fromARGB(20, 204, 89, 51),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _translucentTextFixtureImage() async {
  const width = 240;
  const height = 120;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(60, 35, 120, 50),
      const ui.Radius.circular(10),
    ),
    ui.Paint()..color = const ui.Color.fromARGB(20, 24, 119, 210),
  );
  final glyphPaint = ui.Paint()
    ..color = const ui.Color.fromARGB(255, 24, 119, 210)
    ..strokeWidth = 8
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(
    const ui.Offset(105, 48),
    const ui.Offset(135, 72),
    glyphPaint,
  );
  canvas.drawLine(
    const ui.Offset(135, 48),
    const ui.Offset(105, 72),
    glyphPaint,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _thinHighResolutionFixtureImage() async {
  const width = 2400;
  const height = 1200;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawLine(
    const ui.Offset(180, 601),
    const ui.Offset(2220, 601),
    ui.Paint()
      ..color = const ui.Color(0xFF151515)
      ..strokeWidth = 1,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _largeCancellationFixtureImage() async {
  const width = 1200;
  const height = 800;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..color = const ui.Color(0xFF151515)
    ..strokeWidth = 2;
  for (var x = 10.0; x < width; x += 12) {
    canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, height.toDouble()), paint);
  }
  for (var y = 10.0; y < height; y += 12) {
    canvas.drawLine(ui.Offset(0, y), ui.Offset(width.toDouble(), y), paint);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
