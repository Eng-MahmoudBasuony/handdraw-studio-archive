import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

void main() {
  const validator = MaskCoverageValidator();

  test('accepts a centerline that covers the foreground once', () {
    const width = 20;
    const height = 20;
    final foreground = Uint8List(width * height);
    for (var y = 8; y <= 12; y++) {
      for (var x = 2; x <= 17; x++) {
        foreground[y * width + x] = 1;
      }
    }

    final result = validator.validate(
      foreground: foreground,
      width: width,
      height: height,
      paths: const [
        [Offset(0.1, 0.5), Offset(0.85, 0.5)],
      ],
      revealWidths: const [0.25],
    );

    expect(result.coverage, greaterThanOrEqualTo(0.92));
    expect(result.duplicateCoverage, 0);
    expect(result.passes, isTrue);
  });

  test('reports duplicated coverage for overlapping planned paths', () {
    final foreground = Uint8List(100)..fillRange(0, 100, 1);
    final result = validator.validate(
      foreground: foreground,
      width: 10,
      height: 10,
      paths: const [
        [Offset(0, 0.5), Offset(1, 0.5)],
        [Offset(0, 0.5), Offset(1, 0.5)],
      ],
      revealWidths: const [1, 1],
    );

    expect(result.duplicateCoverage, greaterThan(0.35));
    expect(result.passes, isFalse);
  });

  test('reports real progress throughout expensive path validation', () {
    final foreground = Uint8List(100)..fillRange(0, 100, 1);
    final updates = <double>[];

    validator.validate(
      foreground: foreground,
      width: 10,
      height: 10,
      paths: const [
        [Offset(0, 0.2), Offset(1, 0.2)],
        [Offset(0, 0.4), Offset(1, 0.4)],
        [Offset(0, 0.6), Offset(1, 0.6)],
        [Offset(0, 0.8), Offset(1, 0.8)],
        [Offset(0.2, 0), Offset(0.2, 1)],
      ],
      revealWidths: const [0.2, 0.2, 0.2, 0.2, 0.2],
      onProgress: updates.add,
    );

    expect(updates.first, 0);
    expect(updates.last, 1);
    expect(updates, orderedEquals([...updates]..sort()));
  });
}
