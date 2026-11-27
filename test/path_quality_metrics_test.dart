import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/quality/domain/path_quality_metrics.dart';

void main() {
  test(
    'quality evaluator reports coverage, leakage, duplication, and travel',
    () {
      BinaryPixelMask mask(List<int> values) => BinaryPixelMask(
        width: 4,
        height: 1,
        pixels: Uint8List.fromList(values),
      );

      final report = const PathQualityEvaluator().evaluate(
        source: mask([1, 1, 1, 1]),
        completedReveal: mask([1, 1, 1, 0]),
        earlyReveal: mask([1, 0, 1, 0]),
        allowedEarlyReveal: mask([1, 0, 0, 0]),
        paths: const [
          [QualityPoint(0, 0), QualityPoint(0.25, 0)],
          [QualityPoint(0.75, 0), QualityPoint(1, 0)],
        ],
        coverageCounts: const [1, 2, 1, 0],
        branchOrderScore: 0.8,
        analysisTimeMilliseconds: 42,
        peakMemoryBytes: 1024,
        deterministic: true,
      );

      expect(report.coverage, 0.75);
      expect(report.leakage, 0.25);
      expect(report.duplicateCoverage, 0.25);
      expect(report.penLiftCount, 1);
      expect(report.travelRatio, 1);
      expect(report.branchOrderScore, 0.8);
      expect(report.deterministic, isTrue);
    },
  );

  test('quality evaluator rejects masks with different dimensions', () {
    final source = BinaryPixelMask(
      width: 2,
      height: 1,
      pixels: Uint8List.fromList([1, 1]),
    );
    final wrong = BinaryPixelMask(
      width: 1,
      height: 1,
      pixels: Uint8List.fromList([1]),
    );

    expect(
      () => const PathQualityEvaluator().evaluate(
        source: source,
        completedReveal: wrong,
        earlyReveal: source,
        allowedEarlyReveal: source,
        paths: const [],
        branchOrderScore: 1,
        analysisTimeMilliseconds: 0,
        peakMemoryBytes: 0,
        deterministic: true,
      ),
      throwsArgumentError,
    );
  });
}
