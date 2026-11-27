import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum PlaybackStatus { stopped, playing, paused, ended, disposed }

enum PlayAfterEndPolicy { restartFromBeginning }

final class PlaybackClockState {
  const PlaybackClockState({
    required this.currentTime,
    required this.status,
    required this.playbackRate,
  });

  final TimelineTime currentTime;
  final PlaybackStatus status;
  final double playbackRate;
}

abstract interface class MonotonicTimeSource {
  int get elapsedMicroseconds;
}

abstract interface class PlaybackTickHandle {
  void cancel();
}

abstract interface class PlaybackTickScheduler {
  PlaybackTickHandle schedule(void Function() onTick);
}

typedef PlaybackClockListener = void Function(PlaybackClockState state);

/// Master project clock. Audio and visual consumers are followers.
final class PlaybackClock {
  PlaybackClock({
    required TimelineDuration duration,
    required MonotonicTimeSource timeSource,
    required PlaybackTickScheduler tickScheduler,
    this.playAfterEndPolicy = PlayAfterEndPolicy.restartFromBeginning,
    // Public dependency names are clearer than exposing private field names.
    // ignore: prefer_initializing_formals
  }) : _duration = duration,
       // ignore: prefer_initializing_formals
       _timeSource = timeSource,
       // ignore: prefer_initializing_formals
       _tickScheduler = tickScheduler;

  final TimelineDuration _duration;
  final MonotonicTimeSource _timeSource;
  final PlaybackTickScheduler _tickScheduler;
  final PlayAfterEndPolicy playAfterEndPolicy;
  final Set<PlaybackClockListener> _listeners = {};

  TimelineTime _position = TimelineTime.zero;
  PlaybackStatus _status = PlaybackStatus.stopped;
  double _playbackRate = 1;
  int _anchorElapsedUs = 0;
  TimelineTime _anchorPosition = TimelineTime.zero;
  PlaybackTickHandle? _tickHandle;

  TimelineDuration get duration => _duration;
  TimelineTime get currentTime => _resolvedTime();
  PlaybackStatus get status => _status;
  double get playbackRate => _playbackRate;
  PlaybackClockState get state => PlaybackClockState(
    currentTime: currentTime,
    status: _status,
    playbackRate: _playbackRate,
  );

  void addListener(PlaybackClockListener listener) => _listeners.add(listener);
  void removeListener(PlaybackClockListener listener) =>
      _listeners.remove(listener);

  void play() {
    _ensureActive();
    if (_status == PlaybackStatus.playing) return;
    if (_status == PlaybackStatus.ended &&
        playAfterEndPolicy == PlayAfterEndPolicy.restartFromBeginning) {
      _position = TimelineTime.zero;
    }
    if (_duration.isZero) {
      _position = TimelineTime.zero;
      _status = PlaybackStatus.ended;
      _notify();
      return;
    }
    _anchorPosition = _position;
    _anchorElapsedUs = _timeSource.elapsedMicroseconds;
    _status = PlaybackStatus.playing;
    _tickHandle ??= _tickScheduler.schedule(_tick);
    _notify();
  }

  void pause() {
    _ensureActive();
    if (_status != PlaybackStatus.playing) return;
    _position = _resolvedTime();
    _cancelTicker();
    _status = _position.microseconds == _duration.microseconds
        ? PlaybackStatus.ended
        : PlaybackStatus.paused;
    _notify();
  }

  void stop() {
    _ensureActive();
    _cancelTicker();
    _position = TimelineTime.zero;
    _status = PlaybackStatus.stopped;
    _notify();
  }

  void seek(TimelineTime time) {
    _ensureActive();
    final wasPlaying = _status == PlaybackStatus.playing;
    _position = time.clampTo(_duration);
    _anchorPosition = _position;
    _anchorElapsedUs = _timeSource.elapsedMicroseconds;
    if (_position.microseconds == _duration.microseconds) {
      _cancelTicker();
      _status = PlaybackStatus.ended;
    } else if (!wasPlaying && _status == PlaybackStatus.ended) {
      _status = PlaybackStatus.paused;
    }
    _notify();
  }

  void setPlaybackRate(double rate) {
    _ensureActive();
    if (!rate.isFinite || rate <= 0) {
      throw RangeError.value(rate, 'rate', 'Playback rate must be positive.');
    }
    if (_status == PlaybackStatus.playing) {
      _position = _resolvedTime();
      _anchorPosition = _position;
      _anchorElapsedUs = _timeSource.elapsedMicroseconds;
    }
    _playbackRate = rate;
    _notify();
  }

  /// App lifecycle adapters call this; the clock has no Flutter dependency.
  void pauseForLifecycle() => pause();

  void dispose() {
    if (_status == PlaybackStatus.disposed) return;
    _cancelTicker();
    _status = PlaybackStatus.disposed;
    _notify();
    _listeners.clear();
  }

  void _tick() {
    if (_status != PlaybackStatus.playing) return;
    _position = _resolvedTime();
    if (_position.microseconds == _duration.microseconds) {
      _cancelTicker();
      _status = PlaybackStatus.ended;
    }
    _notify();
  }

  TimelineTime _resolvedTime() {
    if (_status != PlaybackStatus.playing) return _position;
    final elapsed = _timeSource.elapsedMicroseconds - _anchorElapsedUs;
    final advanced = (elapsed * _playbackRate).round();
    return TimelineTime.fromMicroseconds(
      (_anchorPosition.microseconds + advanced).clamp(
        0,
        _duration.microseconds,
      ),
    );
  }

  void _notify() {
    final snapshot = state;
    for (final listener in [..._listeners]) {
      listener(snapshot);
    }
  }

  void _cancelTicker() {
    _tickHandle?.cancel();
    _tickHandle = null;
  }

  void _ensureActive() {
    if (_status == PlaybackStatus.disposed) {
      throw StateError('PlaybackClock is disposed.');
    }
  }
}
