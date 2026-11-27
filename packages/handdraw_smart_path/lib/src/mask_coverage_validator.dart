import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

class MaskCoverageValidation {
  const MaskCoverageValidation({
    required this.coverage,
    required this.duplicateCoverage,
  });

  final double coverage;
  final double duplicateCoverage;

  bool get passes => coverage >= 0.92 && duplicateCoverage <= 0.35;
}

/// Rasterizes planned centerlines into a compact mask before animation.
class MaskCoverageValidator {
  const MaskCoverageValidator();

  MaskCoverageValidation validate({
    required Uint8List foreground,
    required int width,
    required int height,
    required List<List<ui.Offset>> paths,
    required List<double> revealWidths,
    void Function(double fraction)? onProgress,
  }) {
    if (foreground.length != width * height ||
        paths.length != revealWidths.length) {
      throw ArgumentError('Coverage validator inputs have incompatible sizes.');
    }
    final counts = Uint16List(width * height);
    final touchedGeneration = Uint32List(width * height);
    final diskOffsets = <int, List<(int, int)>>{};
    for (var pathIndex = 0; pathIndex < paths.length; pathIndex++) {
      if (pathIndex % 4 == 0) {
        onProgress?.call(pathIndex / math.max(1, paths.length));
      }
      final path = paths[pathIndex];
      if (path.length < 2) continue;
      final radius = math.max(1, (revealWidths[pathIndex] * height / 2).ceil());
      final offsets = diskOffsets.putIfAbsent(
        radius,
        () => _diskOffsets(radius),
      );
      final generation = pathIndex + 1;
      final touched = <int>[];
      var lastX = -1;
      var lastY = -1;
      for (var index = 1; index < path.length; index++) {
        final start = path[index - 1];
        final end = path[index];
        final steps = math.max(
          1,
          ((end - start).distance * math.max(width, height)).ceil(),
        );
        for (var step = 0; step <= steps; step++) {
          final progress = step / steps;
          final x = ((start.dx + (end.dx - start.dx) * progress) * width)
              .round();
          final y = ((start.dy + (end.dy - start.dy) * progress) * height)
              .round();
          if (x == lastX && y == lastY) continue;
          lastX = x;
          lastY = y;
          for (final (dx, dy) in offsets) {
            final px = x + dx;
            final py = y + dy;
            if (px < 0 || px >= width || py < 0 || py >= height) continue;
            final pixel = py * width + px;
            if (touchedGeneration[pixel] == generation) continue;
            touchedGeneration[pixel] = generation;
            touched.add(pixel);
          }
        }
      }
      for (final pixel in touched) {
        if (counts[pixel] < 65535) counts[pixel]++;
      }
    }
    onProgress?.call(1);
    var foregroundCount = 0;
    var covered = 0;
    var duplicated = 0;
    for (var index = 0; index < foreground.length; index++) {
      if (foreground[index] == 0) continue;
      foregroundCount++;
      if (counts[index] > 0) covered++;
      if (counts[index] > 1) duplicated++;
    }
    final denominator = math.max(1, foregroundCount);
    return MaskCoverageValidation(
      coverage: covered / denominator,
      duplicateCoverage: duplicated / denominator,
    );
  }
}

List<(int, int)> _diskOffsets(int radius) {
  final result = <(int, int)>[];
  final squaredRadius = radius * radius;
  for (var dy = -radius; dy <= radius; dy++) {
    for (var dx = -radius; dx <= radius; dx++) {
      if (dx * dx + dy * dy <= squaredRadius) result.add((dx, dy));
    }
  }
  return result;
}
