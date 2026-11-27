import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_transform.dart';

void main() {
  test('records camera overlay transform p50 p95 and memory for large tracks', () {
    const transform = CameraCanvasTransform(
      Rect.fromLTWH(0, 0, 1920, 1080),
      16 / 9,
    );
    for (final count in [100, 500, 1000]) {
      final views = List.generate(
        count,
        (index) => CameraView(
          centerX: (index % 100) / 100,
          centerY: ((index * 7) % 100) / 100,
          viewportWidth: .2 + (index % 20) / 100,
        ),
      );
      final samples = <int>[];
      for (var iteration = 0; iteration < 30; iteration++) {
        final watch = Stopwatch()..start();
        for (final view in views) {
          transform.frameFor(view);
        }
        watch.stop();
        samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      final p50 = samples[(samples.length * .50).floor()];
      final p95 = samples[(samples.length * .95).floor()];
      // Visible in CI logs and the 6E handoff report; no machine-specific gate.
      // ignore: avoid_print
      print(
        'camera_canvas count=$count p50=${p50}us p95=${p95}us rss=${ProcessInfo.currentRss}',
      );
      expect(p95, lessThan(100000));
    }
  });
}
