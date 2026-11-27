import 'dart:io';

import 'package:flutter/services.dart';

import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_synthesizer.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_library.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';

class WritingAudioService {
  WritingAudioService({WritingSoundSynthesizer? synthesizer})
    : _synthesizer = synthesizer ?? const WritingSoundSynthesizer();

  static const _channel = MethodChannel('handdraw_studio/exporter');
  final WritingSoundSynthesizer _synthesizer;
  File? _previewFile;
  CompiledTimeline? _timeline;

  void configureTimeline(CompiledTimeline timeline) => _timeline = timeline;

  Future<void> play(
    HandDrawProject project, {
    VoiceGuide? voiceGuide,
    double positionSeconds = 0,
    double? previewDurationSeconds,
    double volume = 1,
  }) async {
    await stop();
    if (project.writingSoundEnabled) {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-preview-audio-',
      );
      final file = File('${directory.path}/writing-sound.wav');
      final recordedClip = await WritingSoundLibrary.load(
        project.writingSoundPreset,
      );
      await file.writeAsBytes(
        _synthesizer.synthesize(
          project,
          recordedClip: recordedClip,
          timeline: _timeline,
        ),
        flush: true,
      );
      _previewFile = file;
    }
    await _invokeSafely('playPreviewAudio', {
      if (_previewFile != null) 'writingPath': _previewFile!.path,
      if (voiceGuide != null) ...{
        'voicePath': voiceGuide.path,
        'voiceBookmark': voiceGuide.securityBookmark,
      },
      'positionSeconds': positionSeconds,
      'durationSeconds':
          previewDurationSeconds ?? projectTimelineDuration(project),
      'volume': volume.clamp(0.0, 1.0),
    });
  }

  Future<void> pause() => _invokeSafely('pausePreviewAudio');

  Future<void> resume() => _invokeSafely('resumePreviewAudio');

  Future<void> seek(double positionSeconds) =>
      _invokeSafely('seekPreviewAudio', {'positionSeconds': positionSeconds});

  Future<void> setVolume(double volume) => _invokeSafely(
    'setPreviewAudioVolume',
    {'volume': volume.clamp(0.0, 1.0)},
  );

  Future<double> position() async {
    try {
      return await _channel.invokeMethod<double>('getPreviewPosition') ?? 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<void> stop() async {
    await _invokeSafely('stopPreviewAudio');
    final file = _previewFile;
    _previewFile = null;
    if (file != null) {
      try {
        await file.parent.delete(recursive: true);
      } catch (_) {
        // A stale preview file is safe to leave in the system temp directory.
      }
    }
  }

  Future<void> _invokeSafely(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Audio preview is optional on platforms whose native player has not
      // been implemented yet. Export synthesis stays fully cross-platform.
    }
  }
}
