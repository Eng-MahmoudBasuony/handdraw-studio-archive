import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'support/path_runtime_benchmark.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/quality/domain/path_quality_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production path benchmark stays above the checked-in baseline',
    () async {
      final manifest =
          jsonDecode(
                File(
                  'test/fixtures/path_benchmark/manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final baselines = Map<String, dynamic>.from(manifest['cases'] as Map);
      final reports = <String, Object>{};
      final measured = <String, PathQualityReport>{};
      const output = String.fromEnvironment('HANDDRAW_BENCHMARK_OUTPUT');

      for (final fixture in _fixtures()) {
        final image = await fixture.createImage();
        final source = await _sourceMask(image);
        final memoryBefore = ProcessInfo.currentRss;
        final stopwatch = Stopwatch()..start();
        final first = await const SmartPathEngine().analyze(
          image: image,
          encodedImage: Uint8List(0),
        );
        stopwatch.stop();
        final samples = <int>[];
        final sampledRss = <int>[];
        if (const bool.fromEnvironment('HANDDRAW_BENCHMARK_EXTENDED')) {
          for (var repeat = 0; repeat < 5; repeat++) {
            var peak = ProcessInfo.currentRss;
            final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
              peak = math.max(peak, ProcessInfo.currentRss);
            });
            final watch = Stopwatch()..start();
            try {
              await const SmartPathEngine().analyze(
                image: image,
                encodedImage: Uint8List(0),
              );
            } finally {
              samples.add(watch.elapsedMicroseconds);
              sampledRss.add(math.max(peak, ProcessInfo.currentRss));
              timer.cancel();
            }
          }
        }
        final second = await const SmartPathEngine().analyze(
          image: image,
          encodedImage: Uint8List(0),
        );
        final paths = _paths(first);
        final rasterized = _rasterize(
          paths: paths,
          widths: _pathWidths(first),
          width: image.width,
          height: image.height,
        );
        final visible = Uint8List(source.pixels.length);
        for (var index = 0; index < visible.length; index++) {
          visible[index] =
              source.pixels[index] != 0 && rasterized.mask[index] != 0 ? 1 : 0;
        }
        final report = const PathQualityEvaluator().evaluate(
          source: source,
          completedReveal: BinaryPixelMask(
            width: image.width,
            height: image.height,
            pixels: visible,
          ),
          earlyReveal: BinaryPixelMask(
            width: image.width,
            height: image.height,
            pixels: Uint8List(visible.length),
          ),
          allowedEarlyReveal: BinaryPixelMask(
            width: image.width,
            height: image.height,
            pixels: Uint8List(visible.length),
          ),
          paths: paths,
          coverageCounts: rasterized.coverageCounts,
          branchOrderScore: fixture.branchOrderScore(paths),
          analysisTimeMilliseconds: stopwatch.elapsedMilliseconds,
          peakMemoryBytes: math.max(0, ProcessInfo.currentRss - memoryBefore),
          deterministic: _signature(first) == _signature(second),
        );
        reports[fixture.name] = {
          ...report.toJson(),
          'analysisWarmSamplesUs': samples,
          'analysisSampledProcessRssBytes': sampledRss,
          'geometrySignature': _signature(first),
          if (const bool.fromEnvironment('HANDDRAW_BENCHMARK_EXTENDED'))
            'runtime': await benchmarkPathRuntime(
              image,
              first,
              output,
              fixture.name,
            ),
        };
        measured[fixture.name] = report;
        if (output.isNotEmpty) {
          await _writeComparisonArtifacts(
            reportPath: output,
            name: fixture.name,
            source: image,
            revealMask: rasterized.mask,
          );
        }
        image.dispose();
      }

      if (output.isNotEmpty) {
        final file = File(output);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 2,
            'sparseThinning': const bool.fromEnvironment(
              'HANDDRAW_SPIKE_SPARSE_THINNING',
            ),
            'mode': 'flutter-test JIT; no native OCR or MOV encoder',
            'generatedAt': DateTime.now().toUtc().toIso8601String(),
            'cases': reports,
          }),
        );
      }
      for (final entry in measured.entries) {
        if (baselines.containsKey(entry.key)) {
          _expectBaseline(entry.key, entry.value, baselines[entry.key] as Map);
        }
      }
    },
  );
}

void _expectBaseline(String name, PathQualityReport report, Map raw) {
  final baseline = Map<String, dynamic>.from(raw);
  expect(
    report.coverage,
    greaterThanOrEqualTo(baseline['minimumCoverage'] as double),
    reason: '$name coverage regressed',
  );
  expect(
    report.leakage,
    lessThanOrEqualTo(baseline['maximumLeakage'] as double),
    reason: '$name leaks pixels before their section',
  );
  expect(
    report.centerlineError,
    lessThanOrEqualTo(baseline['maximumCenterlineError'] as double),
    reason: '$name pen path moved away from the artwork centerline',
  );
  expect(
    report.travelRatio,
    lessThanOrEqualTo(baseline['maximumTravelRatio'] as double),
    reason: '$name pen travel regressed',
  );
  expect(
    report.penLiftCount,
    lessThanOrEqualTo(baseline['maximumPenLiftCount'] as int),
    reason: '$name adds unnecessary pen lifts',
  );
  expect(
    report.duplicateCoverage,
    lessThanOrEqualTo(baseline['maximumDuplicateCoverage'] as double),
    reason: '$name redraws too much artwork',
  );
  expect(
    report.branchOrderScore,
    greaterThanOrEqualTo(baseline['minimumBranchOrderScore'] as double),
    reason: '$name branch order regressed',
  );
  expect(
    report.analysisTimeMilliseconds,
    lessThanOrEqualTo(baseline['maximumAnalysisMilliseconds'] as int),
    reason: '$name analysis became too slow',
  );
  expect(
    report.peakMemoryBytes,
    lessThanOrEqualTo(baseline['maximumPeakMemoryBytes'] as int),
    reason: '$name analysis used too much additional resident memory',
  );
  expect(report.deterministic, isTrue, reason: '$name is not deterministic');
}

Future<void> _writeComparisonArtifacts({
  required String reportPath,
  required String name,
  required ui.Image source,
  required Uint8List revealMask,
}) async {
  final directory = Directory(
    '${File(reportPath).parent.path}/path_benchmark_comparisons',
  )..createSync(recursive: true);
  final sourcePng = await source.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${directory.path}/${name}_source.png',
  ).writeAsBytes(sourcePng!.buffer.asUint8List());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final points = <ui.Offset>[];
  for (var index = 0; index < revealMask.length; index++) {
    if (revealMask[index] == 0) continue;
    points.add(
      ui.Offset((index % source.width) + 0.5, (index ~/ source.width) + 0.5),
    );
  }
  canvas.drawPoints(
    ui.PointMode.points,
    points,
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..strokeWidth = 1,
  );
  final picture = recorder.endRecording();
  final reveal = await picture.toImage(source.width, source.height);
  picture.dispose();
  final revealPng = await reveal.toByteData(format: ui.ImageByteFormat.png);
  reveal.dispose();
  await File(
    '${directory.path}/${name}_reveal.png',
  ).writeAsBytes(revealPng!.buffer.asUint8List());
}

List<_BenchmarkFixture> _fixtures() => [
  if (const bool.fromEnvironment('HANDDRAW_BENCHMARK_EXTENDED')) ...[
    _BenchmarkFixture(
      'title_1920',
      () => _fileImage('test/fixtures/00-title.png'),
    ),
    _BenchmarkFixture(
      'build_fails_1920',
      () => _fileImage('test/fixtures/04-build-fails.png'),
    ),
  ],
  _BenchmarkFixture('thin_lines', _thinLinesImage),
  _BenchmarkFixture(
    'flowchart_branches',
    _flowchartImage,
    branchOrderScore: _flowchartBranchScore,
  ),
  _BenchmarkFixture('transparent_colored_art', _coloredArtImage),
];

Future<ui.Image> _fileImage(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> _thinLinesImage() => _pictureImage((canvas, paint) {
  paint
    ..color = const ui.Color(0xFF17202A)
    ..strokeWidth = 2
    ..style = ui.PaintingStyle.stroke;
  canvas.drawLine(const ui.Offset(35, 55), const ui.Offset(445, 55), paint);
  canvas.drawLine(const ui.Offset(35, 135), const ui.Offset(445, 135), paint);
  canvas.drawLine(const ui.Offset(35, 215), const ui.Offset(445, 215), paint);
});

Future<ui.Image> _flowchartImage() => _pictureImage((canvas, paint) {
  paint
    ..color = const ui.Color(0xFF2471A3)
    ..strokeWidth = 5
    ..style = ui.PaintingStyle.stroke;
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(190, 20, 100, 45),
      const ui.Radius.circular(8),
    ),
    paint,
  );
  canvas.drawLine(const ui.Offset(240, 65), const ui.Offset(240, 100), paint);
  canvas.drawLine(const ui.Offset(240, 100), const ui.Offset(115, 135), paint);
  canvas.drawLine(const ui.Offset(240, 100), const ui.Offset(365, 135), paint);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(60, 135, 110, 50),
      const ui.Radius.circular(8),
    ),
    paint,
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(310, 135, 110, 50),
      const ui.Radius.circular(8),
    ),
    paint,
  );
  canvas.drawLine(const ui.Offset(115, 185), const ui.Offset(115, 240), paint);
  canvas.drawLine(const ui.Offset(365, 185), const ui.Offset(365, 240), paint);
});

Future<ui.Image> _coloredArtImage() => _pictureImage((canvas, paint) {
  paint
    ..style = ui.PaintingStyle.fill
    ..color = const ui.Color(0xAA2ECC71);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(45, 55, 160, 150),
      const ui.Radius.circular(22),
    ),
    paint,
  );
  paint.color = const ui.Color(0xCCF39C12);
  canvas.drawCircle(const ui.Offset(340, 130), 72, paint);
});

Future<ui.Image> _pictureImage(
  void Function(ui.Canvas canvas, ui.Paint paint) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  draw(canvas, ui.Paint()..isAntiAlias = false);
  final picture = recorder.endRecording();
  final image = await picture.toImage(480, 270);
  picture.dispose();
  return image;
}

Future<BinaryPixelMask> _sourceMask(ui.Image image) async {
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final mask = Uint8List(image.width * image.height);
  for (var pixel = 0; pixel < mask.length; pixel++) {
    mask[pixel] = rgba[pixel * 4 + 3] > 8 ? 1 : 0;
  }
  return BinaryPixelMask(
    width: image.width,
    height: image.height,
    pixels: mask,
  );
}

List<List<QualityPoint>> _paths(SmartPathAnalysis analysis) => [
  for (final section in analysis.sections)
    for (final path in section.paths)
      [for (final point in path.points) QualityPoint(point.dx, point.dy)],
];

List<double> _pathWidths(SmartPathAnalysis analysis) => [
  for (final section in analysis.sections)
    for (final _ in section.paths) section.recommendedRevealWidth,
];

_RasterizedPaths _rasterize({
  required List<List<QualityPoint>> paths,
  required List<double> widths,
  required int width,
  required int height,
}) {
  final counts = List<int>.filled(width * height, 0);
  for (var pathIndex = 0; pathIndex < paths.length; pathIndex++) {
    final path = paths[pathIndex];
    final coveredByPath = <int>{};
    final radius = math.max(1, (widths[pathIndex] * height / 2).ceil());
    for (var index = 1; index < path.length; index++) {
      final start = path[index - 1];
      final end = path[index];
      final distance = math.max(
        1,
        (start.distanceTo(end) * math.max(width, height)).ceil(),
      );
      for (var step = 0; step <= distance; step++) {
        final t = step / distance;
        final x = ((start.x + (end.x - start.x) * t) * width).round();
        final y = ((start.y + (end.y - start.y) * t) * height).round();
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            if (dx * dx + dy * dy > radius * radius) continue;
            final px = x + dx;
            final py = y + dy;
            if (px < 0 || px >= width || py < 0 || py >= height) continue;
            coveredByPath.add(py * width + px);
          }
        }
      }
    }
    for (final pixel in coveredByPath) {
      counts[pixel]++;
    }
  }
  return _RasterizedPaths(
    coverageCounts: counts,
    mask: Uint8List.fromList([for (final count in counts) count > 0 ? 1 : 0]),
  );
}

String _signature(SmartPathAnalysis analysis) => jsonEncode([
  for (final section in analysis.sections)
    {
      'kind': section.kind.name,
      'width': section.recommendedRevealWidth,
      'mode': section.mode.name,
      'bounds': [
        section.bounds.left,
        section.bounds.top,
        section.bounds.right,
        section.bounds.bottom,
      ],
      'paths': [
        for (final path in section.paths)
          [
            for (final point in path.points) [point.dx, point.dy],
          ],
      ],
    },
]);

double _flowchartBranchScore(List<List<QualityPoint>> paths) {
  final branches = <int>[];
  for (final path in paths) {
    if (path.isEmpty) continue;
    final centerX = path.fold(0.0, (sum, point) => sum + point.x) / path.length;
    final centerY = path.fold(0.0, (sum, point) => sum + point.y) / path.length;
    if (centerY < 0.42 || (centerX > 0.42 && centerX < 0.58)) continue;
    branches.add(centerX < 0.5 ? 0 : 1);
  }
  if (branches.length < 2) return 1;
  var changes = 0;
  for (var index = 1; index < branches.length; index++) {
    if (branches[index] != branches[index - 1]) changes++;
  }
  return changes <= 1 ? 1 : 1 / changes;
}

class _BenchmarkFixture {
  const _BenchmarkFixture(
    this.name,
    this.createImage, {
    this.branchOrderScore = _perfectBranchScore,
  });

  final String name;
  final Future<ui.Image> Function() createImage;
  final double Function(List<List<QualityPoint>>) branchOrderScore;
}

double _perfectBranchScore(List<List<QualityPoint>> _) => 1;

class _RasterizedPaths {
  const _RasterizedPaths({required this.mask, required this.coverageCounts});

  final Uint8List mask;
  final List<int> coverageCounts;
}
