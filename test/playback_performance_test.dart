import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';

const _run = bool.fromEnvironment('HANDDRAW_RUN_PLAYBACK_BENCHMARK');
final _clockFrequency = Stopwatch().frequency;

void main() {
  test(
    'records master-clock tick plus resolver cost',
    () {
      final time = _Time();
      final scheduler = _Scheduler();
      final timeline = _timeline(1000);
      final clock = PlaybackClock(
        duration: timeline.duration,
        timeSource: time,
        tickScheduler: scheduler,
      );
      const resolver = GlobalTimelineResolver();
      var checksum = 0;
      clock.addListener((state) {
        final frame = resolver.resolveAt(timeline, state.currentTime);
        checksum =
            ((checksum * 31) ^
                frame.time.microseconds ^
                (frame.drawing?.sectionId?.hashCode ?? 0)) &
            0x7fffffff;
      });
      clock.play();
      for (var iteration = 0; iteration < 1000; iteration++) {
        time.value += 100;
        scheduler.tick();
      }
      final samples = <int>[];
      for (var iteration = 0; iteration < 20000; iteration++) {
        time.value += 100;
        final watch = Stopwatch()..start();
        scheduler.tick();
        samples.add(watch.elapsedTicks);
      }
      samples.sort();
      double us(num ticks) => ticks * 1000000 / _clockFrequency;
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      // ignore: avoid_print
      print(
        'PLAYBACK_TICK mode=debug_jit sections=1000 n=20000 clock_hz=$_clockFrequency mean_us=${us(mean).toStringAsFixed(3)} median_us=${us(samples[9999]).toStringAsFixed(3)} p95_us=${us(samples[18999]).toStringAsFixed(3)} p99_us=${us(samples[19799]).toStringAsFixed(3)} checksum=$checksum',
      );
      expect(checksum, isNot(0));
    },
    skip: _run
        ? false
        : 'Opt-in with --dart-define=HANDDRAW_RUN_PLAYBACK_BENCHMARK=true',
  );
}

CompiledTimeline _timeline(int count) {
  final sectionDuration = 10000;
  return CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: ProjectId('benchmark'),
      documentRevision: 1,
    ),
    duration: TimelineDuration.fromMicroseconds(count * sectionDuration),
    contentEnd: TimelineTime.fromMicroseconds(count * sectionDuration),
    drawing: CompiledDrawingTimelineTrack(
      interval: TimelineInterval(
        start: TimelineTime.zero,
        end: TimelineTime.fromMicroseconds(count * sectionDuration),
      ),
      sections: [
        for (var index = 0; index < count; index++)
          CompiledDrawingSection(
            sectionId: SectionId('section-$index'),
            interval: TimelineInterval(
              start: TimelineTime.fromMicroseconds(index * sectionDuration),
              end: TimelineTime.fromMicroseconds((index + 1) * sectionDuration),
            ),
          ),
      ],
    ),
    audio: const [],
    voiceGuide: null,
    sceneMarkers: const [],
  );
}

final class _Time implements MonotonicTimeSource {
  int value = 0;
  @override
  int get elapsedMicroseconds => value;
}

final class _Scheduler implements PlaybackTickScheduler {
  void Function()? callback;
  void tick() => callback?.call();
  @override
  PlaybackTickHandle schedule(void Function() onTick) {
    callback = onTick;
    return _Handle(() => callback = null);
  }
}

final class _Handle implements PlaybackTickHandle {
  _Handle(this.cancelCallback);
  final void Function() cancelCallback;
  @override
  void cancel() => cancelCallback();
}
