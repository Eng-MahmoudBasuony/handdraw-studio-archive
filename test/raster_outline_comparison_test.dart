import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/raster_outline_analysis.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_outline_analysis_service.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/outline_fill_reveal_planner.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all outline engines produce deterministic scored candidates', () {
    final buffer = _syntheticArtwork();
    const comparator = RasterOutlineComparator();
    final first = comparator.compare(buffer);
    final second = comparator.compare(buffer);

    expect(first.candidates, hasLength(3));
    expect(
      first.candidates.map((item) => item.mask.algorithm).toSet(),
      RasterOutlineAlgorithm.values.toSet(),
    );
    expect(first.winner.metrics.score, greaterThan(.30));
    for (final candidate in first.candidates) {
      expect(candidate.metrics.edgePixelCount, greaterThan(0));
      expect(candidate.metrics.score, inInclusiveRange(0, 1));
      final repeated = second.candidate(candidate.mask.algorithm);
      expect(repeated.mask.edges, orderedEquals(candidate.mask.edges));
      expect(repeated.metrics.score, candidate.metrics.score);
    }
  });

  for (final fixture in const ['00-title.png', '04-build-fails.png']) {
    test('compares Adaptive, Canny+, and Morph Shell on $fixture', () async {
      final source = await File('test/fixtures/$fixture').readAsBytes();
      final bytes = await _flattenOnWhite(source);
      final comparison = await const RasterOutlineAnalysisService(
        maximumAnalysisDimension: 360,
      ).analyze(bytes);

      expect(comparison, isNotNull);
      expect(comparison!.candidates, hasLength(3));
      expect(comparison.winner.metrics.score, greaterThan(.30));
      expect(comparison.winner.metrics.edgePixelCount, greaterThan(80));
      expect(comparison.winner.metrics.borderEdgeFraction, lessThan(.35));
      expect(
        comparison.winner.mask.algorithm,
        RasterOutlineAlgorithm.cannyPlus,
        reason: 'Canny+ scored best on both checked-in real artworks.',
      );
    });
  }

  test('smart regions stay progressive in the shared renderer', () async {
    final source = await File('test/fixtures/00-title.png').readAsBytes();
    final bytes = await _flattenOnWhite(source);
    final project = HandDrawProject(
      canvasWidth: 320,
      canvasHeight: 180,
      durationSeconds: 3,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );
    final plan = await const OutlineFillRevealPlanner(
      analysisService: RasterOutlineAnalysisService(
        maximumAnalysisDimension: 320,
      ),
    ).build(encoded: bytes, project: project);

    expect(plan.usedSafeFallback, isFalse);
    expect(plan.strokes.length, greaterThan(60));
    expect(
      plan.strokes,
      everyElement(
        isA<DrawingStroke>().having(
          (stroke) => stroke.sectionId,
          'shared smart region section',
          'auto-smart-region-reveal',
        ),
      ),
    );
    expect(
      plan.strokes,
      everyElement(
        isA<DrawingStroke>().having(
          (stroke) => stroke.id,
          'smart region id',
          startsWith('auto-smart-region-'),
        ),
      ),
    );
    for (final stroke in plan.strokes) {
      final xs = stroke.points.map((point) => point.dx);
      final ys = stroke.points.map((point) => point.dy);
      expect(
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
        lessThan(.1),
      );
      expect(
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        lessThan(.02),
      );
    }
    final drawing = await _decode(bytes, width: 320, height: 180);
    final plannedProject = project.copyWith(strokes: plan.strokes);
    final sourceVisible = await _visiblePixelCount(drawing);
    final early = await const FrameRenderer().render(
      project: plannedProject,
      drawing: drawing,
      hand: null,
      progress: .28,
    );
    final middle = await const FrameRenderer().render(
      project: plannedProject,
      drawing: drawing,
      hand: null,
      progress: .78,
    );
    final end = await const FrameRenderer().render(
      project: plannedProject,
      drawing: drawing,
      hand: null,
      progress: 1,
    );

    final earlyVisible = await _visiblePixelCount(early);
    final middleVisible = await _visiblePixelCount(middle);
    final endVisible = await _visiblePixelCount(end);
    expect(earlyVisible, greaterThan(0));
    expect(middleVisible, greaterThan(earlyVisible));
    expect(endVisible, sourceVisible);
    await expectLater(
      early,
      matchesGoldenFile('goldens/smart_region_reveal_title_28.png'),
    );
    await expectLater(
      middle,
      matchesGoldenFile('goldens/smart_region_reveal_title_78.png'),
    );

    early.dispose();
    middle.dispose();
    end.dispose();
    drawing.dispose();
  });

  test(
    'uncertain or undecodable artwork keeps the safe diagonal fallback',
    () async {
      final plan = await const OutlineFillRevealPlanner().build(
        encoded: Uint8List.fromList(const [1, 2, 3, 4]),
        project: HandDrawProject(canvasWidth: 320, canvasHeight: 180),
      );

      expect(plan.usedSafeFallback, isTrue);
      expect(plan.strokes, hasLength(1));
      expect(plan.strokes.single.id, startsWith('auto-opaque-reveal-'));
    },
  );
}

RasterPixelBuffer _syntheticArtwork() {
  const width = 96;
  const height = 64;
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final inBlock = x >= 18 && x <= 76 && y >= 14 && y <= 48;
      final onInk =
          inBlock &&
          (x <= 21 || x >= 73 || y <= 17 || y >= 45 || (x - y).abs() < 2);
      rgba[offset] = onInk ? 20 : 248;
      rgba[offset + 1] = onInk ? 72 : 248;
      rgba[offset + 2] = onInk ? 160 : 248;
      rgba[offset + 3] = 255;
    }
  }
  return RasterPixelBuffer(width: width, height: height, rgba: rgba);
}

Future<ui.Image> _decode(
  Uint8List bytes, {
  required int width,
  required int height,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Uint8List> _flattenOnWhite(Uint8List bytes) async {
  final source = await _decode(bytes, width: 640, height: 360);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
    ..drawImage(source, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final flattened = await picture.toImage(640, 360);
  final encoded = await flattened.toByteData(format: ui.ImageByteFormat.png);
  source.dispose();
  flattened.dispose();
  picture.dispose();
  return encoded!.buffer.asUint8List();
}

Future<int> _visiblePixelCount(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var count = 0;
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] > 0) count++;
  }
  return count;
}
