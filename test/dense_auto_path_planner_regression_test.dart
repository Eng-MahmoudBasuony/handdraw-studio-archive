import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  test('indexed dense ordering matches the exact legacy nearest walk', () {
    final paths = _generatedPaths(128);
    final expected = _legacyOrder(paths);
    final actual = const AutoPathStrokePlanner()
        .build(sections: [_section(paths)], project: HandDrawProject())
        .strokes
        .map((stroke) => stroke.orderedPoints)
        .toList(growable: false);

    expect(actual, hasLength(expected.length));
    for (var index = 0; index < expected.length; index++) {
      expect(actual[index], orderedEquals(expected[index]));
    }
  });

  test('indexed dense ordering preserves direction-locked connector paths', () {
    final paths = _generatedPaths(128);
    final expected = _legacyOrder(paths, allowReverse: false);
    final actual = const AutoPathStrokePlanner()
        .build(
          sections: [_section(paths, role: SmartSectionRole.connector)],
          project: HandDrawProject(),
        )
        .strokes
        .map((stroke) => stroke.orderedPoints)
        .toList(growable: false);

    expect(actual, hasLength(expected.length));
    for (var index = 0; index < expected.length; index++) {
      expect(actual[index], orderedEquals(expected[index]));
    }
  });

  test('8062 generated paths are planned without a quadratic UI stall', () {
    final paths = _generatedPaths(8062);
    final watch = Stopwatch()..start();
    final plan = const AutoPathStrokePlanner().build(
      sections: [_section(paths)],
      project: HandDrawProject(),
    );
    watch.stop();

    expect(plan.strokes, hasLength(paths.length));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason:
          'Dense scene planning must use the exact spatial index rather than '
          'an O(paths²) nearest-neighbour scan.',
    );
  });

  test(
    '8062 generated paths are planned away from the UI event loop',
    () async {
      final paths = _generatedPaths(8062);
      final planner = const AutoPathStrokePlanner();
      var heartbeatRan = false;
      Timer.run(() => heartbeatRan = true);

      final plan = await planner.buildResponsive(
        sections: [_section(paths)],
        project: HandDrawProject(),
      );

      expect(heartbeatRan, isTrue);
      expect(plan.strokes, hasLength(paths.length));
      expect(
        plan.strokes.first.orderedPoints,
        orderedEquals(
          planner
              .build(sections: [_section(paths)], project: HandDrawProject())
              .strokes
              .first
              .orderedPoints,
        ),
      );
    },
  );

  test('cancelling an 8062-path plan stops its worker isolate', () async {
    final operation = const AutoPathStrokePlanner().startResponsive(
      sections: [_section(_generatedPaths(8062))],
      project: HandDrawProject(),
    );
    await operation.workerStarted;
    final cancelledResult = expectLater(
      operation.result,
      throwsA(isA<AutoPathPlanningCancelled>()),
    );

    await operation.cancel();

    await cancelledResult;
    await operation.stopped;
    expect(operation.isWorkerRunning, isFalse);
  });
}

SmartPathSection _section(
  List<SmartGeneratedPath> paths, {
  SmartSectionRole role = SmartSectionRole.content,
}) => SmartPathSection(
  id: 'dense-scene',
  kind: SmartSectionKind.shape,
  bounds: const Rect.fromLTWH(0, 0, 1, 1),
  label: 'Dense scene',
  paths: paths,
  recommendedRevealWidth: 0.008,
  mode: SmartSectionMode.handDraw,
  role: role,
);

List<SmartGeneratedPath> _generatedPaths(int count) =>
    List.generate(count, (index) {
      final x = ((index * 7919) % 9973) / 10500 + 0.015;
      final y = ((index * 6151 + 17) % 9967) / 10500 + 0.015;
      final angle = (index * 0.61803398875) % (math.pi * 2);
      final delta = Offset(math.cos(angle), math.sin(angle)) * 0.004;
      final start = Offset(x.clamp(0.01, 0.98), y.clamp(0.01, 0.98));
      final end = Offset(
        (start.dx + delta.dx).clamp(0.001, 0.999),
        (start.dy + delta.dy).clamp(0.001, 0.999),
      );
      return SmartGeneratedPath(points: [start, end]);
    });

List<List<Offset>> _legacyOrder(
  List<SmartGeneratedPath> paths, {
  bool allowReverse = true,
}) {
  final remaining = [for (final path in paths) List<Offset>.of(path.points)]
    ..sort((left, right) {
      final leftCenter = (left.first + left.last) / 2;
      final rightCenter = (right.first + right.last) / 2;
      final vertical = leftCenter.dy.compareTo(rightCenter.dy);
      return vertical != 0 ? vertical : leftCenter.dx.compareTo(rightCenter.dx);
    });
  final result = <List<Offset>>[remaining.removeAt(0)];
  while (remaining.isNotEmpty) {
    final end = result.last.last;
    var bestIndex = 0;
    var reverse = false;
    var bestDistance = double.infinity;
    for (var index = 0; index < remaining.length; index++) {
      final startDistance = (remaining[index].first - end).distance;
      final endDistance = allowReverse
          ? (remaining[index].last - end).distance
          : double.infinity;
      final distance = math.min(startDistance, endDistance);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
        reverse = endDistance < startDistance;
      }
    }
    final next = remaining.removeAt(bestIndex);
    result.add(reverse ? next.reversed.toList(growable: false) : next);
  }
  return result;
}
