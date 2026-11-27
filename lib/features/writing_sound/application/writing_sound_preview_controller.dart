import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_preview_player.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_preview_service.dart';

enum WritingSoundPreviewStatus { idle, loading, playing, failed }

/// Owns the lifecycle of a short writing-sound sample.
class WritingSoundPreviewController extends ChangeNotifier {
  WritingSoundPreviewController({required this.player});

  final WritingSoundPreviewPlayer player;
  Timer? _progressTimer;
  Stopwatch? _stopwatch;
  int _generation = 0;
  WritingSoundPreset? _activePreset;
  WritingSoundPreviewStatus _status = WritingSoundPreviewStatus.idle;
  double _progress = 0;

  WritingSoundPreviewStatus get status => _status;
  double get progress => _progress;
  bool get isBusy =>
      _status == WritingSoundPreviewStatus.loading ||
      _status == WritingSoundPreviewStatus.playing;

  Future<void> toggle({
    required WritingSoundPreset preset,
    required double volume,
  }) async {
    if (isBusy && _activePreset == preset) {
      await stop();
      return;
    }
    await play(preset: preset, volume: volume);
  }

  Future<void> play({
    required WritingSoundPreset preset,
    required double volume,
  }) async {
    final generation = ++_generation;
    await _stopPlayback(notify: false);
    if (generation != _generation) return;
    _activePreset = preset;
    _status = WritingSoundPreviewStatus.loading;
    _progress = 0;
    notifyListeners();
    try {
      await player.play(preset: preset, volume: volume);
      if (generation != _generation) {
        await player.stop();
        return;
      }
      _status = WritingSoundPreviewStatus.playing;
      _stopwatch = Stopwatch()..start();
      _progressTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _updateProgress(generation),
      );
      notifyListeners();
    } catch (_) {
      if (generation != _generation) return;
      _status = WritingSoundPreviewStatus.failed;
      _progress = 0;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _generation++;
    await _stopPlayback(notify: true);
  }

  void _updateProgress(int generation) {
    if (generation != _generation || _stopwatch == null) return;
    final elapsed = _stopwatch!.elapsedMilliseconds;
    final duration = WritingSoundPreviewService.sampleDuration.inMilliseconds;
    _progress = (elapsed / duration).clamp(0.0, 1.0);
    if (_progress >= 1) {
      unawaited(stop());
    } else {
      notifyListeners();
    }
  }

  Future<void> _stopPlayback({required bool notify}) async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    await player.stop();
    _activePreset = null;
    _status = WritingSoundPreviewStatus.idle;
    _progress = 0;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _progressTimer?.cancel();
    unawaited(player.stop());
    super.dispose();
  }
}
