import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/compiled_camera_track.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_resolver.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_timeline_compiler.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

const _run = bool.fromEnvironment('HANDDRAW_RUN_CAMERA_BENCHMARK');
final _clockFrequency = Stopwatch().frequency;
void main() {
  test('camera compile and random/sequential resolve benchmark', () {
    for (final count in [40, 200, 1000]) {
      final track = _track(count);
      final key = TimelineDependencyKey(
        projectId: ProjectId('perf'),
        documentRevision: 1,
      );
      final compileSamples = <int>[];
      late CompiledCameraTrack compiled;
      for (var i = 0; i < 50; i++) {
        final watch = Stopwatch()..start();
        compiled = const CameraTimelineCompiler().compile(
          track: track,
          dependencyKey: key,
        );
        watch.stop();
        compileSamples.add(watch.elapsedTicks);
      }
      final random = math.Random(42);
      final randomSamples = <int>[];
      final sequentialSamples = <int>[];
      var checksum = 0.0;
      for (var i = 0; i < 10000; i++) {
        var watch = Stopwatch()..start();
        final randomFrame = const CameraResolver().resolveAt(
          compiled,
          TimelineTime.fromMicroseconds(random.nextInt(count * 10000)),
        );
        watch.stop();
        randomSamples.add(watch.elapsedTicks);
        checksum += _signature(randomFrame);
        watch = Stopwatch()..start();
        final sequentialFrame = const CameraResolver().resolveAt(
          compiled,
          // Spread 10,000 samples over the entire track, not just shot one.
          TimelineTime.fromMicroseconds(i * count),
        );
        watch.stop();
        sequentialSamples.add(watch.elapsedTicks);
        checksum += _signature(sequentialFrame);
      }
      compileSamples.sort();
      randomSamples.sort();
      sequentialSamples.sort();
      // ignore: avoid_print
      print(
        'CAMERA_PERF mode=debug_jit shots=$count clock_hz=$_clockFrequency checksum=$checksum compile_mean_us=${_mean(compileSamples)} compile_p95_us=${_p(compileSamples, .95)} random_mean_us=${_mean(randomSamples)} random_p95_us=${_p(randomSamples, .95)} random_p99_us=${_p(randomSamples, .99)} sequential_mean_us=${_mean(sequentialSamples)} sequential_p95_us=${_p(sequentialSamples, .95)}',
      );
      expect(compiled.shots, hasLength(count));
      expect(checksum.isFinite, isTrue);
      expect(checksum, greaterThan(0));
    }
  }, skip: !_run ? 'Opt-in with HANDDRAW_RUN_CAMERA_BENCHMARK=true' : null);
}

double _signature(ResolvedCameraState frame) => switch (frame) {
  ResolvedSingleCameraView(:final view) => view.viewportWidth,
  ResolvedCameraBlend(:final fromView, :final toView, :final targetOpacity) =>
    fromView.viewportWidth + toView.viewportWidth + targetOpacity,
};

String _micros(num ticks) => (ticks * 1e6 / _clockFrequency).toStringAsFixed(3);
String _mean(List<int> values) =>
    _micros(values.reduce((a, b) => a + b) / values.length);
String _p(List<int> values, double p) =>
    _micros(values[((values.length - 1) * p).round()]);
ProjectCameraTrack _track(int count) => ProjectCameraTrack(
  id: CameraTrackId('track'),
  shots: [
    for (var i = 0; i < count; i++)
      CameraShot(
        id: CameraShotId('s$i'),
        startTime: TimelineTime.fromMicroseconds(i * 10000),
        duration: TimelineDuration.fromMicroseconds(9000),
        authorship: CameraAuthorship.manual,
        isLocked: false,
        keyframes: [
          CameraKeyframe(
            id: CameraKeyframeId('a$i'),
            offset: TimelineTime.zero,
            view: const CameraView.identity(),
          ),
          CameraKeyframe(
            id: CameraKeyframeId('b$i'),
            offset: TimelineTime.fromMicroseconds(3000),
            view: const CameraView(centerX: 2, centerY: -1, viewportWidth: .25),
            incomingTransition: CameraTransition(
              type: CameraTransitionType.move,
              duration: TimelineDuration.fromMicroseconds(2000),
              easing: CameraEasing.easeInOut,
            ),
          ),
          CameraKeyframe(
            id: CameraKeyframeId('c$i'),
            offset: TimelineTime.fromMicroseconds(7000),
            view: const CameraView(centerX: -2, centerY: 1, viewportWidth: 4),
            incomingTransition: CameraTransition(
              type: CameraTransitionType.fade,
              duration: TimelineDuration.fromMicroseconds(1000),
            ),
          ),
        ],
      ),
  ],
);
