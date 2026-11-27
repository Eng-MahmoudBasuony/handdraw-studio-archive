import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Converts a one-pixel skeleton graph into deterministic pen trails.
///
/// Every raster edge is visited once. At junctions the planner prefers the
/// straightest continuation, then orders the resulting trails by minimum pen
/// travel while allowing a trail to be reversed.
class SkeletonGraphPlanner {
  const SkeletonGraphPlanner();

  List<List<ui.Offset>> buildTrails(Uint8List skeleton, int width, int height) {
    final visitedEdges = <int>{};
    final trails = <List<ui.Offset>>[];
    int edgeKey(int a, int b) {
      final low = math.min(a, b);
      final high = math.max(a, b);
      return low * skeleton.length + high;
    }

    List<int> activeNeighbors(int index) =>
        _neighbors(index, skeleton, width, height);
    List<int> unvisitedNeighbors(int index) => activeNeighbors(index)
        .where((neighbor) => !visitedEdges.contains(edgeKey(index, neighbor)))
        .toList(growable: false);

    int chooseNext(int current, int? previous, List<int> candidates) {
      if (previous == null || candidates.length == 1) return candidates.first;
      final currentX = current % width;
      final currentY = current ~/ width;
      final incomingX = currentX - previous % width;
      final incomingY = currentY - previous ~/ width;
      candidates.sort((a, b) {
        final aX = a % width - currentX;
        final aY = a ~/ width - currentY;
        final bX = b % width - currentX;
        final bY = b ~/ width - currentY;
        final aDot = incomingX * aX + incomingY * aY;
        final bDot = incomingX * bX + incomingY * bY;
        final straightness = bDot.compareTo(aDot);
        return straightness != 0 ? straightness : a.compareTo(b);
      });
      return candidates.first;
    }

    void traceTrail(int start) {
      final indices = <int>[start];
      int? previous;
      var current = start;
      while (true) {
        final candidates = unvisitedNeighbors(current);
        if (candidates.isEmpty) break;
        final next = chooseNext(current, previous, candidates);
        visitedEdges.add(edgeKey(current, next));
        indices.add(next);
        previous = current;
        current = next;
      }
      if (indices.length < 2) return;
      trails.add(
        indices
            .map(
              (index) => ui.Offset(
                (index % width).toDouble(),
                (index ~/ width).toDouble(),
              ),
            )
            .toList(growable: false),
      );
    }

    final active = <int>[];
    final odd = <int>[];
    for (var index = 0; index < skeleton.length; index++) {
      if (skeleton[index] == 0) continue;
      active.add(index);
      if (activeNeighbors(index).length.isOdd) odd.add(index);
    }
    for (final start in [...odd, ...active]) {
      while (unvisitedNeighbors(start).isNotEmpty) {
        traceTrail(start);
      }
    }
    return _minimizePenTravel(trails);
  }

  List<List<ui.Offset>> _minimizePenTravel(List<List<ui.Offset>> source) {
    if (source.length < 2) return source;
    final remaining = List<List<ui.Offset>>.of(source);
    remaining.sort((a, b) {
      final vertical = a.first.dy.compareTo(b.first.dy);
      return vertical != 0 ? vertical : a.first.dx.compareTo(b.first.dx);
    });
    final ordered = <List<ui.Offset>>[remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final current = ordered.last.last;
      var bestIndex = 0;
      var reverse = false;
      var bestDistance = double.infinity;
      for (var index = 0; index < remaining.length; index++) {
        final path = remaining[index];
        final toStart = (path.first - current).distanceSquared;
        final toEnd = (path.last - current).distanceSquared;
        final candidateDistance = math.min(toStart, toEnd);
        if (candidateDistance < bestDistance) {
          bestDistance = candidateDistance;
          bestIndex = index;
          reverse = toEnd < toStart;
        }
      }
      final next = remaining.removeAt(bestIndex);
      ordered.add(reverse ? next.reversed.toList(growable: false) : next);
    }
    return ordered;
  }

  List<int> _neighbors(int index, Uint8List skeleton, int width, int height) {
    final x = index % width;
    final y = index ~/ width;
    final result = <int>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final neighbor = ny * width + nx;
        if (skeleton[neighbor] == 0) continue;
        if (dx != 0 && dy != 0) {
          final horizontal = y * width + nx;
          final vertical = ny * width + x;
          if (skeleton[horizontal] != 0 || skeleton[vertical] != 0) continue;
        }
        result.add(neighbor);
      }
    }
    return result;
  }
}
