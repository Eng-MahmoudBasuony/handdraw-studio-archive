import 'dart:async';

import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';

final class StopwatchMonotonicTimeSource implements MonotonicTimeSource {
  StopwatchMonotonicTimeSource() : _stopwatch = Stopwatch()..start();
  final Stopwatch _stopwatch;
  @override
  int get elapsedMicroseconds => _stopwatch.elapsedMicroseconds;
}

final class TimerPlaybackTickScheduler implements PlaybackTickScheduler {
  const TimerPlaybackTickScheduler({
    this.interval = const Duration(milliseconds: 16),
  });
  final Duration interval;

  @override
  PlaybackTickHandle schedule(void Function() onTick) =>
      _TimerTickHandle(Timer.periodic(interval, (_) => onTick()));
}

final class _TimerTickHandle implements PlaybackTickHandle {
  _TimerTickHandle(this._timer);
  final Timer _timer;
  @override
  void cancel() => _timer.cancel();
}
