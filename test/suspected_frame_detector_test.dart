import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

void main() {
  const detector = SuspectedFrameDetector();

  test('accepts only an almost-full-canvas closed rectangular contour', () {
    final assessment = detector.assess(
      _section(
        bounds: const Rect.fromLTRB(0.01, 0.01, 0.99, 0.99),
        points: const [
          Offset(0.01, 0.01),
          Offset(0.50, 0.01),
          Offset(0.99, 0.01),
          Offset(0.99, 0.50),
          Offset(0.99, 0.99),
          Offset(0.50, 0.99),
          Offset(0.01, 0.99),
          Offset(0.01, 0.50),
          Offset(0.01, 0.01),
        ],
      ),
    );

    expect(assessment.isCandidate, isTrue);
    expect(assessment.confidence, greaterThanOrEqualTo(0.96));
  });

  test('rejects an intentional inset card or phone border', () {
    final assessment = detector.assess(
      _section(
        bounds: const Rect.fromLTRB(0.10, 0.08, 0.90, 0.92),
        points: const [
          Offset(0.10, 0.08),
          Offset(0.90, 0.08),
          Offset(0.90, 0.92),
          Offset(0.10, 0.92),
          Offset(0.10, 0.08),
          Offset(0.50, 0.08),
          Offset(0.90, 0.50),
          Offset(0.50, 0.92),
        ],
      ),
    );

    expect(assessment.isCandidate, isFalse);
  });

  test('rejects a full-width underline and an open three-sided shape', () {
    final underline = detector.assess(
      _section(
        bounds: const Rect.fromLTRB(0.01, 0.49, 0.99, 0.51),
        points: const [
          Offset(0.01, 0.50),
          Offset(0.15, 0.50),
          Offset(0.30, 0.50),
          Offset(0.45, 0.50),
          Offset(0.60, 0.50),
          Offset(0.75, 0.50),
          Offset(0.90, 0.50),
          Offset(0.99, 0.50),
        ],
      ),
    );
    final openShape = detector.assess(
      _section(
        bounds: const Rect.fromLTRB(0.01, 0.01, 0.99, 0.99),
        points: const [
          Offset(0.01, 0.01),
          Offset(0.50, 0.01),
          Offset(0.99, 0.01),
          Offset(0.99, 0.50),
          Offset(0.99, 0.99),
          Offset(0.75, 0.99),
          Offset(0.50, 0.99),
          Offset(0.25, 0.99),
        ],
      ),
    );

    expect(underline.isCandidate, isFalse);
    expect(openShape.isCandidate, isFalse);
  });
}

SmartPathSection _section({
  required Rect bounds,
  required List<Offset> points,
}) => SmartPathSection(
  id: 'shape',
  kind: SmartSectionKind.shape,
  bounds: bounds,
  label: 'Artwork',
  paths: [SmartGeneratedPath(points: points)],
  recommendedRevealWidth: 0.01,
  mode: SmartSectionMode.handDraw,
);
