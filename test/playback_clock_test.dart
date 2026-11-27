import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/playback/application/playback_lifecycle_adapter.dart';
import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test(
    'play pause resume rate seek stop and ended policy are deterministic',
    () {
      final time = _FakeTime();
      final scheduler = _FakeScheduler();
      final clock = PlaybackClock(
        duration: _duration(1000000),
        timeSource: time,
        tickScheduler: scheduler,
      );
      final states = <PlaybackClockState>[];
      clock.addListener(states.add);

      clock.play();
      time.advance(200000);
      scheduler.tick();
      expect(clock.currentTime.microseconds, 200000);
      clock.pause();
      time.advance(200000);
      expect(clock.currentTime.microseconds, 200000);

      clock.setPlaybackRate(2);
      clock.play();
      time.advance(100000);
      scheduler.tick();
      expect(clock.currentTime.microseconds, 400000);
      clock.seek(_time(900000));
      time.advance(50000);
      scheduler.tick();
      expect(clock.currentTime.microseconds, 1000000);
      expect(clock.status, PlaybackStatus.ended);

      clock.play();
      expect(clock.currentTime, TimelineTime.zero);
      expect(clock.status, PlaybackStatus.playing);
      clock.stop();
      expect(clock.state.status, PlaybackStatus.stopped);
      expect(clock.currentTime, TimelineTime.zero);
      expect(states, isNotEmpty);
    },
  );

  test('seek clamps to end and works while paused or playing', () {
    final time = _FakeTime();
    final scheduler = _FakeScheduler();
    final clock = PlaybackClock(
      duration: _duration(100),
      timeSource: time,
      tickScheduler: scheduler,
    );

    clock.seek(_time(1000));
    expect(clock.currentTime.microseconds, 100);
    expect(clock.status, PlaybackStatus.ended);
    clock.seek(TimelineTime.zero);
    expect(clock.status, PlaybackStatus.paused);
    clock.play();
    clock.seek(_time(50));
    time.advance(10);
    expect(clock.currentTime.microseconds, 60);
    clock.pauseForLifecycle();
    expect(clock.status, PlaybackStatus.paused);
  });

  test('zero duration ends immediately and dispose cancels callbacks', () {
    final scheduler = _FakeScheduler();
    final clock = PlaybackClock(
      duration: TimelineDuration.zero,
      timeSource: _FakeTime(),
      tickScheduler: scheduler,
    );
    clock.play();
    expect(clock.status, PlaybackStatus.ended);
    expect(scheduler.active, isFalse);
    clock.dispose();
    expect(clock.status, PlaybackStatus.disposed);
    expect(clock.play, throwsStateError);
  });

  test(
    'framework-neutral lifecycle adapter pauses and resumes only active play',
    () {
      final clock = PlaybackClock(
        duration: _duration(100),
        timeSource: _FakeTime(),
        tickScheduler: _FakeScheduler(),
      );
      final lifecycle = PlaybackLifecycleAdapter(clock);
      lifecycle.onAppPaused();
      expect(clock.status, PlaybackStatus.stopped);
      clock.play();
      lifecycle.onAppPaused();
      expect(clock.status, PlaybackStatus.paused);
      lifecycle.onAppResumed();
      expect(clock.status, PlaybackStatus.playing);
      lifecycle.onAppPaused();
      lifecycle.cancelPendingResume();
      lifecycle.onAppResumed();
      expect(clock.status, PlaybackStatus.paused);
    },
  );
}

TimelineTime _time(int us) => TimelineTime.fromMicroseconds(us);
TimelineDuration _duration(int us) => TimelineDuration.fromMicroseconds(us);

final class _FakeTime implements MonotonicTimeSource {
  int value = 0;
  void advance(int us) => value += us;
  @override
  int get elapsedMicroseconds => value;
}

final class _FakeScheduler implements PlaybackTickScheduler {
  void Function()? callback;
  bool get active => callback != null;
  void tick() => callback?.call();
  @override
  PlaybackTickHandle schedule(void Function() onTick) {
    callback = onTick;
    return _FakeHandle(() => callback = null);
  }
}

final class _FakeHandle implements PlaybackTickHandle {
  _FakeHandle(this.onCancel);
  final void Function() onCancel;
  @override
  void cancel() => onCancel();
}
