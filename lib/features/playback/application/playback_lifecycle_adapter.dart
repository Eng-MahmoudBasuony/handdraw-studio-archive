import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';

/// Framework-neutral boundary for a future platform lifecycle observer.
final class PlaybackLifecycleAdapter {
  PlaybackLifecycleAdapter(this.clock);

  final PlaybackClock clock;
  bool _resumePlayback = false;

  void onAppPaused() {
    _resumePlayback = clock.status == PlaybackStatus.playing;
    if (_resumePlayback) clock.pauseForLifecycle();
  }

  void onAppResumed() {
    if (!_resumePlayback) return;
    _resumePlayback = false;
    clock.play();
  }

  void cancelPendingResume() => _resumePlayback = false;
}
