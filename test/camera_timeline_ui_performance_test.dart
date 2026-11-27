import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/application/camera_timeline_viewport_query.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('40/200/1000 viewport query cost follows visible shots', () {
    const query = CameraTimelineViewportQuery();
    for (final count in [40, 200, 1000]) {
      final shots = _shots(count);
      final samples = <int>[];
      var visibleCount = 0;
      var maxVisible = 0;
      for (var index = 0; index < 1000; index++) {
        final watch = Stopwatch()..start();
        visibleCount = query
            .visibleShots(
              shots: shots,
              viewportStart: (index % count) * 100.0,
              viewportWidth: 900,
              pixelsPerSecond: 100,
            )
            .length;
        watch.stop();
        samples.add(watch.elapsedMicroseconds);
        if (visibleCount > maxVisible) maxVisible = visibleCount;
      }
      samples.sort();
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      final p95 = samples[(samples.length * .95).floor()];
      // Printed values are copied to the checked-in acceptance report.
      // ignore: avoid_print
      print(
        'camera viewport $count: mean=${mean.toStringAsFixed(2)}us p95=${p95}us maxVisible=$maxVisible',
      );
      expect(maxVisible, lessThanOrEqualTo(11));
      expect(p95, lessThan(1000));
    }
  });

  test('600 playback resolves reuse one compile and never revise document', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    final revision = cubit.state.documentRevision;
    final compiled = cubit.compileTimeline();
    for (var tick = 0; tick < 600; tick++) {
      expect(identical(cubit.compileTimeline(), compiled), isTrue);
    }
    expect(cubit.state.documentRevision, revision);
  });

  testWidgets('300 playhead ticks do not repaint Camera clips', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    final revision = cubit.state.documentRevision;
    final diagnostics = CameraTimelineDiagnostics();
    final tick = ValueNotifier(0);
    addTearDown(tick.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (context, value, _) => EditorTimelineDock(
            cubit: cubit,
            previewProgress: value / 300,
            isPreviewing: true,
            onSeek: (_) {},
            onPreviewStroke: (_) {},
            onTimingChangeStart: () {},
            onTimingChangeEnd: () {},
            playheadTime: TimelineTime.fromMicroseconds(value),
            cameraDiagnostics: diagnostics,
          ),
        ),
      ),
    );
    await tester.pump();
    final initialPaints = diagnostics.painterRepaints;
    for (var value = 1; value <= 300; value++) {
      tick.value = value;
      await tester.pump();
    }
    expect(diagnostics.painterRepaints, initialPaints);
    expect(cubit.state.documentRevision, revision);
  });
}

List<CameraShot> _shots(int count) => [
  for (var index = 0; index < count; index++)
    CameraShot(
      id: CameraShotId('shot-$index'),
      startTime: TimelineTime.fromMicroseconds(index * 1000000),
      duration: TimelineDuration.fromMicroseconds(900000),
      authorship: CameraAuthorship.manual,
      isLocked: false,
      keyframes: [
        CameraKeyframe(
          id: CameraKeyframeId('key-$index'),
          offset: TimelineTime.zero,
          view: const CameraView.identity(),
        ),
      ],
    ),
];
