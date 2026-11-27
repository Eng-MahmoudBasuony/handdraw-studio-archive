import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

enum RasterOutlineAlgorithm { adaptive, cannyPlus, morphShell }

final class RasterPixelBuffer {
  RasterPixelBuffer({
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : assert(width > 0 && height > 0),
       assert(rgba.length == width * height * 4),
       rgba = Uint8List.fromList(rgba),
       luminance = _buildLuminance(rgba, width * height);

  final int width;
  final int height;
  final Uint8List rgba;
  final Uint8List luminance;

  int index(int x, int y) => y * width + x;

  static Uint8List _buildLuminance(Uint8List rgba, int pixelCount) {
    final result = Uint8List(pixelCount);
    for (var index = 0; index < pixelCount; index++) {
      final source = index * 4;
      result[index] =
          (rgba[source] * 0.299 +
                  rgba[source + 1] * 0.587 +
                  rgba[source + 2] * 0.114)
              .round();
    }
    return result;
  }
}

final class RasterOutlineMask {
  RasterOutlineMask({
    required this.algorithm,
    required this.width,
    required this.height,
    required Uint8List edges,
  }) : assert(edges.length == width * height),
       edges = Uint8List.fromList(edges);

  final RasterOutlineAlgorithm algorithm;
  final int width;
  final int height;
  final Uint8List edges;

  bool contains(int x, int y) => edges[y * width + x] != 0;
}

final class RasterOutlineMetrics {
  const RasterOutlineMetrics({
    required this.edgePixelCount,
    required this.componentCount,
    required this.edgeDensity,
    required this.largestComponentFraction,
    required this.borderEdgeFraction,
    required this.score,
  });

  final int edgePixelCount;
  final int componentCount;
  final double edgeDensity;
  final double largestComponentFraction;
  final double borderEdgeFraction;
  final double score;
}

final class RasterOutlineCandidate {
  const RasterOutlineCandidate({required this.mask, required this.metrics});

  final RasterOutlineMask mask;
  final RasterOutlineMetrics metrics;
}

final class RasterOutlineComparison {
  RasterOutlineComparison({
    required Iterable<RasterOutlineCandidate> candidates,
    required this.winner,
  }) : candidates = List.unmodifiable(candidates);

  final List<RasterOutlineCandidate> candidates;
  final RasterOutlineCandidate winner;

  RasterOutlineCandidate candidate(RasterOutlineAlgorithm algorithm) =>
      candidates.singleWhere((item) => item.mask.algorithm == algorithm);
}

abstract interface class RasterOutlineDetector {
  RasterOutlineAlgorithm get algorithm;

  RasterOutlineMask detect(RasterPixelBuffer image);
}

final class AdaptiveRasterOutlineDetector implements RasterOutlineDetector {
  const AdaptiveRasterOutlineDetector({this.minimumContrast = 11});

  final int minimumContrast;

  @override
  RasterOutlineAlgorithm get algorithm => RasterOutlineAlgorithm.adaptive;

  @override
  RasterOutlineMask detect(RasterPixelBuffer image) {
    final width = image.width;
    final height = image.height;
    final integralWidth = width + 1;
    final integral = Int64List(integralWidth * (height + 1));
    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      for (var x = 0; x < width; x++) {
        rowSum += image.luminance[image.index(x, y)];
        integral[(y + 1) * integralWidth + x + 1] =
            integral[y * integralWidth + x + 1] + rowSum;
      }
    }
    var radius = math.max(3, math.min(width, height) ~/ 28);
    if (radius.isEven) radius++;
    final foreground = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final top = math.max(0, y - radius);
      final bottom = math.min(height, y + radius + 1);
      for (var x = 0; x < width; x++) {
        final left = math.max(0, x - radius);
        final right = math.min(width, x + radius + 1);
        final sum =
            integral[bottom * integralWidth + right] -
            integral[top * integralWidth + right] -
            integral[bottom * integralWidth + left] +
            integral[top * integralWidth + left];
        final mean = sum / ((right - left) * (bottom - top));
        final luminance = image.luminance[image.index(x, y)];
        if ((luminance - mean).abs() >= minimumContrast) {
          foreground[image.index(x, y)] = 1;
        }
      }
    }
    return RasterOutlineMask(
      algorithm: algorithm,
      width: width,
      height: height,
      edges: _boundaryOf(foreground, width, height),
    );
  }
}

final class CannyPlusRasterOutlineDetector implements RasterOutlineDetector {
  const CannyPlusRasterOutlineDetector({this.highPercentile = .82});

  final double highPercentile;

  @override
  RasterOutlineAlgorithm get algorithm => RasterOutlineAlgorithm.cannyPlus;

  @override
  RasterOutlineMask detect(RasterPixelBuffer image) {
    final width = image.width;
    final height = image.height;
    final magnitudes = Float32List(width * height);
    final nonZero = <double>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        int sample(int dx, int dy) =>
            image.luminance[image.index(x + dx, y + dy)];
        final gx =
            -sample(-1, -1) +
            sample(1, -1) -
            2 * sample(-1, 0) +
            2 * sample(1, 0) -
            sample(-1, 1) +
            sample(1, 1);
        final gy =
            -sample(-1, -1) -
            2 * sample(0, -1) -
            sample(1, -1) +
            sample(-1, 1) +
            2 * sample(0, 1) +
            sample(1, 1);
        final magnitude = math.sqrt((gx * gx + gy * gy).toDouble());
        magnitudes[image.index(x, y)] = magnitude;
        if (magnitude > 0) nonZero.add(magnitude);
      }
    }
    if (nonZero.isEmpty) {
      return RasterOutlineMask(
        algorithm: algorithm,
        width: width,
        height: height,
        edges: Uint8List(width * height),
      );
    }
    nonZero.sort();
    final percentileIndex =
        ((nonZero.length - 1) * highPercentile.clamp(.55, .95)).round();
    final high = math.max(18.0, nonZero[percentileIndex]);
    final low = high * .42;
    final edges = Uint8List(width * height);
    final weak = Uint8List(width * height);
    final queue = Queue<int>();
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final index = image.index(x, y);
        final magnitude = magnitudes[index];
        if (magnitude >= high) {
          edges[index] = 1;
          queue.add(index);
        } else if (magnitude >= low) {
          weak[index] = 1;
        }
      }
    }
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      final x = index % width;
      final y = index ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final neighbor = (y + dy) * width + x + dx;
          if (weak[neighbor] == 0 || edges[neighbor] != 0) continue;
          edges[neighbor] = 1;
          queue.add(neighbor);
        }
      }
    }
    return RasterOutlineMask(
      algorithm: algorithm,
      width: width,
      height: height,
      edges: edges,
    );
  }
}

final class MorphShellRasterOutlineDetector implements RasterOutlineDetector {
  const MorphShellRasterOutlineDetector({this.colorDistanceThreshold = 30});

  final int colorDistanceThreshold;

  @override
  RasterOutlineAlgorithm get algorithm => RasterOutlineAlgorithm.morphShell;

  @override
  RasterOutlineMask detect(RasterPixelBuffer image) {
    final width = image.width;
    final height = image.height;
    var red = 0;
    var green = 0;
    var blue = 0;
    var samples = 0;
    void include(int x, int y) {
      final offset = image.index(x, y) * 4;
      red += image.rgba[offset];
      green += image.rgba[offset + 1];
      blue += image.rgba[offset + 2];
      samples++;
    }

    for (var x = 0; x < width; x++) {
      include(x, 0);
      if (height > 1) include(x, height - 1);
    }
    for (var y = 1; y < height - 1; y++) {
      include(0, y);
      if (width > 1) include(width - 1, y);
    }
    final backgroundRed = red / samples;
    final backgroundGreen = green / samples;
    final backgroundBlue = blue / samples;
    final foreground = Uint8List(width * height);
    final thresholdSquared = colorDistanceThreshold * colorDistanceThreshold;
    for (var index = 0; index < width * height; index++) {
      final offset = index * 4;
      final dr = image.rgba[offset] - backgroundRed;
      final dg = image.rgba[offset + 1] - backgroundGreen;
      final db = image.rgba[offset + 2] - backgroundBlue;
      final distanceSquared = dr * dr + dg * dg + db * db;
      if (distanceSquared >= thresholdSquared) foreground[index] = 1;
    }
    return RasterOutlineMask(
      algorithm: algorithm,
      width: width,
      height: height,
      edges: _boundaryOf(foreground, width, height),
    );
  }
}

final class RasterOutlineComparator {
  const RasterOutlineComparator({
    this.detectors = const [
      AdaptiveRasterOutlineDetector(),
      CannyPlusRasterOutlineDetector(),
      MorphShellRasterOutlineDetector(),
    ],
  });

  final List<RasterOutlineDetector> detectors;

  RasterOutlineComparison compare(RasterPixelBuffer image) {
    if (detectors.isEmpty) {
      throw StateError('At least one outline detector is required.');
    }
    final candidates = [
      for (final detector in detectors) _candidate(detector.detect(image)),
    ];
    candidates.sort((a, b) => b.metrics.score.compareTo(a.metrics.score));
    return RasterOutlineComparison(
      candidates: candidates,
      winner: candidates.first,
    );
  }

  RasterOutlineCandidate _candidate(RasterOutlineMask mask) {
    final edges = mask.edges;
    final width = mask.width;
    final height = mask.height;
    final visited = Uint8List(edges.length);
    var edgeCount = 0;
    var borderCount = 0;
    var components = 0;
    var largestComponent = 0;
    for (var index = 0; index < edges.length; index++) {
      if (edges[index] == 0) continue;
      edgeCount++;
      final x = index % width;
      final y = index ~/ width;
      if (x <= 1 || y <= 1 || x >= width - 2 || y >= height - 2) {
        borderCount++;
      }
      if (visited[index] != 0) continue;
      components++;
      var componentSize = 0;
      final queue = Queue<int>()..add(index);
      visited[index] = 1;
      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        componentSize++;
        final currentX = current % width;
        final currentY = current ~/ width;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nextX = currentX + dx;
            final nextY = currentY + dy;
            if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) {
              continue;
            }
            final next = nextY * width + nextX;
            if (edges[next] == 0 || visited[next] != 0) continue;
            visited[next] = 1;
            queue.add(next);
          }
        }
      }
      largestComponent = math.max(largestComponent, componentSize);
    }
    final density = edgeCount / edges.length;
    final continuity = edgeCount == 0 ? 0.0 : largestComponent / edgeCount;
    final borderFraction = edgeCount == 0 ? 1.0 : borderCount / edgeCount;
    final densityScore = (1 - ((density - .055).abs() / .09)).clamp(0.0, 1.0);
    final continuityScore = math.sqrt(continuity.clamp(0.0, 1.0));
    final fragmentationScore = 1 / (1 + math.max(0, components - 18) / 24);
    final enoughEdges = edgeCount >= math.max(12, edges.length * .0015);
    final score = enoughEdges
        ? (.42 * densityScore +
                  .38 * continuityScore +
                  .20 * fragmentationScore -
                  .28 * borderFraction)
              .clamp(0.0, 1.0)
        : 0.0;
    return RasterOutlineCandidate(
      mask: mask,
      metrics: RasterOutlineMetrics(
        edgePixelCount: edgeCount,
        componentCount: components,
        edgeDensity: density,
        largestComponentFraction: continuity,
        borderEdgeFraction: borderFraction,
        score: score,
      ),
    );
  }
}

Uint8List _boundaryOf(Uint8List foreground, int width, int height) {
  final edges = Uint8List(width * height);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final index = y * width + x;
      if (foreground[index] == 0) continue;
      if (foreground[index - 1] == 0 ||
          foreground[index + 1] == 0 ||
          foreground[index - width] == 0 ||
          foreground[index + width] == 0) {
        edges[index] = 1;
      }
    }
  }
  return edges;
}
