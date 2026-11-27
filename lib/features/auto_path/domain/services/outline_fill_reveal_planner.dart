import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:handdraw_studio/features/artwork_analysis/domain/raster_outline_analysis.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_outline_analysis_service.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/opaque_raster_reveal_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

final class OutlineFillRevealPlan {
  OutlineFillRevealPlan({
    required Iterable<DrawingStroke> strokes,
    required this.comparison,
    required this.usedSafeFallback,
  }) : strokes = List.unmodifiable(strokes);

  final List<DrawingStroke> strokes;
  final RasterOutlineComparison? comparison;
  final bool usedSafeFallback;

  RasterOutlineAlgorithm? get selectedAlgorithm =>
      comparison?.winner.mask.algorithm;

  String? get selectedAlgorithmLabel => switch (selectedAlgorithm) {
    RasterOutlineAlgorithm.adaptive => 'Adaptive',
    RasterOutlineAlgorithm.cannyPlus => 'Canny+',
    RasterOutlineAlgorithm.morphShell => 'Morph Shell',
    null => null,
  };
}

/// Reveals an opaque raster as broad, overlapping local regions.
///
/// Edge analysis is deliberately used only as a saliency map. Turning edge
/// pixels directly into strokes produces scattered dashes on photographs.
/// Region strokes instead start around useful detail, grow in connected
/// clusters, and eventually cover the complete source. They remain ordinary
/// reveal strokes, so Preview and MOV share exactly the same timeline.
final class OutlineFillRevealPlanner {
  const OutlineFillRevealPlanner({
    this.analysisService = const RasterOutlineAnalysisService(),
    this.fallbackPlanner = const OpaqueRasterRevealPlanner(),
    this.minimumConfidence = .30,
    this.targetColumns = 14,
    this.newIslandInterval = 9,
  });

  final RasterOutlineAnalysisService analysisService;
  final OpaqueRasterRevealPlanner fallbackPlanner;
  final double minimumConfidence;
  final int targetColumns;
  final int newIslandInterval;

  Future<OutlineFillRevealPlan> build({
    required Uint8List encoded,
    required HandDrawProject project,
  }) async {
    final comparison = await analysisService.analyze(encoded);
    if (comparison == null ||
        comparison.winner.metrics.score < minimumConfidence) {
      return _fallback(project, comparison);
    }
    final strokes = _regionStrokes(comparison.winner.mask, project);
    if (strokes.isEmpty) return _fallback(project, comparison);
    return OutlineFillRevealPlan(
      strokes: strokes,
      comparison: comparison,
      usedSafeFallback: false,
    );
  }

  OutlineFillRevealPlan _fallback(
    HandDrawProject project,
    RasterOutlineComparison? comparison,
  ) => OutlineFillRevealPlan(
    strokes: fallbackPlanner.build(project: project),
    comparison: comparison,
    usedSafeFallback: true,
  );

  List<DrawingStroke> _regionStrokes(
    RasterOutlineMask mask,
    HandDrawProject project,
  ) {
    final columns = targetColumns.clamp(8, 20);
    // Keep cells approximately square in output pixels for every aspect ratio.
    final rows = (columns * mask.height / mask.width).round().clamp(6, 16);
    final cells = <_RevealCell>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          _scoreCell(mask, column, row, columns, rows),
    ];
    if (cells.every((cell) => cell.edgeDensity == 0)) return const [];

    final ordered = _connectedOrder(cells, columns: columns, rows: rows);
    final generation = DateTime.now().microsecondsSinceEpoch;
    final cellHeight = 1 / rows;
    final revealWidth = project.canvasHeight * cellHeight * 1.32;
    return List.unmodifiable([
      for (var index = 0; index < ordered.length; index++)
        _strokeForCell(
          ordered[index],
          index: index,
          generation: generation,
          columns: columns,
          rows: rows,
          revealWidth: revealWidth,
          algorithm: mask.algorithm,
        ),
    ]);
  }

  _RevealCell _scoreCell(
    RasterOutlineMask mask,
    int column,
    int row,
    int columns,
    int rows,
  ) {
    final left = column * mask.width ~/ columns;
    final right = (column + 1) * mask.width ~/ columns;
    final top = row * mask.height ~/ rows;
    final bottom = (row + 1) * mask.height ~/ rows;
    var edges = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (mask.contains(x, y)) edges++;
      }
    }
    final area = math.max(1, (right - left) * (bottom - top));
    final density = edges / area;
    final centerX = (column + .5) / columns;
    final centerY = (row + .5) / rows;
    final distanceFromCenter = math.sqrt(
      math.pow(centerX - .5, 2) + math.pow(centerY - .43, 2),
    );
    final centerBias = (1 - distanceFromCenter / .72).clamp(0.0, 1.0);
    final topBias = 1 - centerY;
    return _RevealCell(
      column: column,
      row: row,
      edgeDensity: density,
      priority: density * .78 + centerBias * .14 + topBias * .08,
    );
  }

  List<_RevealCell> _connectedOrder(
    List<_RevealCell> cells, {
    required int columns,
    required int rows,
  }) {
    final byPosition = <(int, int), _RevealCell>{
      for (final cell in cells) (cell.column, cell.row): cell,
    };
    final remaining = cells.toSet();
    final revealed = <_RevealCell>{};
    final result = <_RevealCell>[];
    final interval = newIslandInterval.clamp(5, 14);

    while (remaining.isNotEmpty) {
      final startNewIsland = result.isEmpty || result.length % interval == 0;
      Iterable<_RevealCell> candidates;
      if (startNewIsland) {
        candidates = remaining;
      } else {
        final frontier = <_RevealCell>{};
        for (final cell in revealed) {
          for (final neighbor in _neighbors(cell, byPosition)) {
            if (remaining.contains(neighbor)) frontier.add(neighbor);
          }
        }
        candidates = frontier.isEmpty ? remaining : frontier;
      }
      final next = candidates.reduce((best, candidate) {
        final bestScore = _growthScore(best, revealed, byPosition);
        final candidateScore = _growthScore(candidate, revealed, byPosition);
        if (candidateScore != bestScore) {
          return candidateScore > bestScore ? candidate : best;
        }
        if (candidate.row != best.row) {
          return candidate.row < best.row ? candidate : best;
        }
        return candidate.column < best.column ? candidate : best;
      });
      remaining.remove(next);
      revealed.add(next);
      result.add(next);
    }
    return result;
  }

  double _growthScore(
    _RevealCell cell,
    Set<_RevealCell> revealed,
    Map<(int, int), _RevealCell> byPosition,
  ) {
    var adjacent = 0;
    for (final neighbor in _neighbors(cell, byPosition)) {
      if (revealed.contains(neighbor)) adjacent++;
    }
    return cell.priority + adjacent * .055;
  }

  Iterable<_RevealCell> _neighbors(
    _RevealCell cell,
    Map<(int, int), _RevealCell> byPosition,
  ) sync* {
    for (var rowDelta = -1; rowDelta <= 1; rowDelta++) {
      for (var columnDelta = -1; columnDelta <= 1; columnDelta++) {
        if (rowDelta == 0 && columnDelta == 0) continue;
        final neighbor =
            byPosition[(cell.column + columnDelta, cell.row + rowDelta)];
        if (neighbor != null) yield neighbor;
      }
    }
  }

  DrawingStroke _strokeForCell(
    _RevealCell cell, {
    required int index,
    required int generation,
    required int columns,
    required int rows,
    required double revealWidth,
    required RasterOutlineAlgorithm algorithm,
  }) {
    final centerX = (cell.column + .5) / columns;
    final centerY = (cell.row + .5) / rows;
    final halfLength = .42 / columns;
    // A small deterministic bend avoids a mechanical tile-grid appearance.
    final bend = ((cell.column * 17 + cell.row * 11) % 7 - 3) / rows * .018;
    final left = Offset(centerX - halfLength, centerY - bend);
    final middle = Offset(centerX, centerY + bend);
    final right = Offset(centerX + halfLength, centerY - bend);
    final points = (cell.column + cell.row).isEven
        ? [left, middle, right]
        : [right, middle, left];
    return DrawingStroke(
      id: 'auto-smart-region-$generation-$index',
      name: 'Smart Region • ${_algorithmLabel(algorithm)}',
      points: points,
      revealOnly: true,
      revealStyle: RevealMaskStyle.brush,
      sectionId: 'auto-smart-region-reveal',
      clipBounds: const Rect.fromLTWH(0, 0, 1, 1),
      revealWidth: revealWidth,
    );
  }
}

final class _RevealCell {
  const _RevealCell({
    required this.column,
    required this.row,
    required this.edgeDensity,
    required this.priority,
  });

  final int column;
  final int row;
  final double edgeDensity;
  final double priority;
}

String _algorithmLabel(RasterOutlineAlgorithm algorithm) => switch (algorithm) {
  RasterOutlineAlgorithm.adaptive => 'Adaptive',
  RasterOutlineAlgorithm.cannyPlus => 'Canny+',
  RasterOutlineAlgorithm.morphShell => 'Morph Shell',
};
