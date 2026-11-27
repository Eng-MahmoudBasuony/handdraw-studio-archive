import 'package:flutter/scheduler.dart';

import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';

/// Flutter ticker boundary. Its timestamp is the injected monotonic source.
final class FlutterPlaybackTickerAdapter
    implements MonotonicTimeSource, PlaybackTickScheduler {
  int _elapsedMicroseconds = 0;

  @override
  int get elapsedMicroseconds => _elapsedMicroseconds;

  @override
  PlaybackTickHandle schedule(void Function() onTick) {
    late final Ticker ticker;
    ticker = Ticker((elapsed) {
      _elapsedMicroseconds = elapsed.inMicroseconds;
      onTick();
    })..start();
    return _FlutterTickerHandle(ticker);
  }
}

final class _FlutterTickerHandle implements PlaybackTickHandle {
  _FlutterTickerHandle(this._ticker);
  final Ticker _ticker;

  @override
  void cancel() {
    _ticker.stop();
    _ticker.dispose();
  }
}
