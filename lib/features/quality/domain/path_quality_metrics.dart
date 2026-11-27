import 'dart:math' as math;
import 'dart:typed_data';

class QualityPoint {
  const QualityPoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(QualityPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class BinaryPixelMask {
  BinaryPixelMask({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : assert(width > 0),
       assert(height > 0),
       assert(pixels.length == width * height),
       pixels = Uint8List.fromList(pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  bool contains(int x, int y) =>
      x >= 0 && x < width && y >= 0 && y < height && pixels[y * width + x] != 0;

  int get visiblePixelCount =>
      pixels.fold(0, (sum, value) => sum + (value > 0 ? 1 : 0));
}

class PathQualityReport {
  const PathQualityReport({
    required this.coverage,
    required this.leakage,
    required this.centerlineError,
    required this.penLiftCount,
    required this.travelRatio,
    required this.duplicateCoverage,
    required this.branchOrderScore,
    required this.analysisTimeMilliseconds,
    required this.peakMemoryBytes,
    required this.deterministic,
  });

  final double coverage;
  final double leakage;
  final double centerlineError;
  final int penLiftCount;
  final double travelRatio;
  final double duplicateCoverage;
  final double branchOrderScore;
  final int analysisTimeMilliseconds;
  final int peakMemoryBytes;
  final bool deterministic;

  Map<String, Object> toJson() => {
    'coverage': coverage,
    'leakage': leakage,
    'centerlineError': centerlineError,
    'penLiftCount': penLiftCount,
    'travelRatio': travelRatio,
    'duplicateCoverage': duplicateCoverage,
    'branchOrderScore': branchOrderScore,
    'analysisTimeMilliseconds': analysisTimeMilliseconds,
    'peakMemoryBytes': peakMemoryBytes,
    'deterministic': deterministic,
  };
}

/// Pure quality evaluator shared by tests, CI benchmarks, and future telemetry.
///
/// Every mask uses one byte per pixel so the evaluator remains transferable to
/// an isolate and never depends on `dart:ui.Image` or `dart:ui.Path`.
class PathQualityEvaluator {
  const PathQualityEvaluator();

  PathQualityReport evaluate({
    required BinaryPixelMask source,
    required BinaryPixelMask completedReveal,
    required BinaryPixelMask earlyReveal,
    required BinaryPixelMask allowedEarlyReveal,
    required List<List<QualityPoint>> paths,
    List<int>? coverageCounts,
    required double branchOrderScore,
    required int analysisTimeMilliseconds,
    required int peakMemoryBytes,
    required bool deterministic,
  }) {
    _requireMatchingMasks(source, completedReveal);
    _requireMatchingMasks(source, earlyReveal);
    _requireMatchingMasks(source, allowedEarlyReveal);
    if (coverageCounts != null &&
        coverageCounts.length != source.pixels.length) {
      throw ArgumentError.value(
        coverageCounts.length,
        'coverageCounts',
        'Coverage counts must match the source dimensions.',
      );
    }

    var sourcePixels = 0;
    var coveredPixels = 0;
    var leakedPixels = 0;
    var duplicatedPixels = 0;
    for (var index = 0; index < source.pixels.length; index++) {
      final belongsToSource = source.pixels[index] != 0;
      if (belongsToSource) {
        sourcePixels++;
        if (completedReveal.pixels[index] != 0) coveredPixels++;
        if ((coverageCounts?[index] ?? 0) > 1) duplicatedPixels++;
      }
      if (earlyReveal.pixels[index] != 0 &&
          allowedEarlyReveal.pixels[index] == 0) {
        leakedPixels++;
      }
    }
    final denominator = math.max(1, sourcePixels);
    final lengths = _pathLengths(paths);
    final drawingLength = lengths.fold(0.0, (sum, length) => sum + length);
    var travelLength = 0.0;
    for (var index = 1; index < paths.length; index++) {
      if (paths[index - 1].isEmpty || paths[index].isEmpty) continue;
      travelLength += paths[index - 1].last.distanceTo(paths[index].first);
    }
    final diagonal = math.sqrt(
      source.width * source.width + source.height * source.height,
    );

    return PathQualityReport(
      coverage: coveredPixels / denominator,
      leakage: leakedPixels / denominator,
      centerlineError: _centerlineError(source, paths) / math.max(1, diagonal),
      penLiftCount: math.max(
        0,
        paths.where((path) => path.length > 1).length - 1,
      ),
      travelRatio: drawingLength <= 0 ? 0 : travelLength / drawingLength,
      duplicateCoverage: duplicatedPixels / denominator,
      branchOrderScore: branchOrderScore.clamp(0, 1),
      analysisTimeMilliseconds: math.max(0, analysisTimeMilliseconds),
      peakMemoryBytes: math.max(0, peakMemoryBytes),
      deterministic: deterministic,
    );
  }

  void _requireMatchingMasks(BinaryPixelMask first, BinaryPixelMask second) {
    if (first.width != second.width || first.height != second.height) {
      throw ArgumentError('All quality masks must have identical dimensions.');
    }
  }

  List<double> _pathLengths(List<List<QualityPoint>> paths) => [
    for (final path in paths)
      if (path.length < 2)
        0
      else
        [
          for (var index = 1; index < path.length; index++)
            path[index - 1].distanceTo(path[index]),
        ].fold(0.0, (sum, length) => sum + length),
  ];

  double _centerlineError(
    BinaryPixelMask source,
    List<List<QualityPoint>> paths,
  ) {
    var total = 0.0;
    var count = 0;
    final maximumRadius = math.max(source.width, source.height);
    for (final path in paths) {
      for (final point in path) {
        final x = (point.x * source.width).floor();
        final y = (point.y * source.height).floor();
        if (source.contains(x, y)) {
          count++;
          continue;
        }
        var nearest = maximumRadius.toDouble();
        search:
        for (var radius = 1; radius <= maximumRadius; radius++) {
          for (var offset = -radius; offset <= radius; offset++) {
            if (source.contains(x + offset, y - radius) ||
                source.contains(x + offset, y + radius) ||
                source.contains(x - radius, y + offset) ||
                source.contains(x + radius, y + offset)) {
              nearest = radius.toDouble();
              break search;
            }
          }
        }
        total += nearest;
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }
}
