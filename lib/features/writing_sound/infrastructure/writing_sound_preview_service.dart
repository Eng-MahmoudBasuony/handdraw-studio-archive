import 'dart:io';

import 'package:flutter/services.dart';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_synthesizer.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_preview_player.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_library.dart';

/// Plays the exact texture used by Preview and Export as a short pen stroke.
class WritingSoundPreviewService implements WritingSoundPreviewPlayer {
  WritingSoundPreviewService({WritingSoundSynthesizer? synthesizer})
    : _synthesizer = synthesizer ?? const WritingSoundSynthesizer();

  static const sampleDuration = Duration(milliseconds: 2200);
  static const _channel = MethodChannel('handdraw_studio/exporter');

  final WritingSoundSynthesizer _synthesizer;
  Directory? _temporaryDirectory;

  @override
  Future<void> play({
    required WritingSoundPreset preset,
    required double volume,
  }) async {
    await stop();
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-writing-sample-',
    );
    _temporaryDirectory = directory;
    final file = File('${directory.path}/writing-sound-sample.wav');
    final recordedClip = await WritingSoundLibrary.load(preset);
    final project = _sampleProject(preset: preset, volume: volume);
    await file.writeAsBytes(
      _synthesizer.synthesize(project, recordedClip: recordedClip),
      flush: true,
    );
    try {
      await _channel.invokeMethod<void>('playWritingAudio', {
        'path': file.path,
      });
    } on MissingPluginException {
      // Sound selection remains usable on platforms without a native player.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopWritingAudio');
    } on MissingPluginException {
      // The preview is optional outside supported desktop hosts.
    }
    final directory = _temporaryDirectory;
    _temporaryDirectory = null;
    if (directory == null) return;
    try {
      await directory.delete(recursive: true);
    } catch (_) {
      // A stale sample in the system temp directory is safe to leave behind.
    }
  }

  HandDrawProject _sampleProject({
    required WritingSoundPreset preset,
    required double volume,
  }) => HandDrawProject(
    durationSeconds: sampleDuration.inMilliseconds / 1000,
    frameRate: 30,
    startDelaySeconds: 0.12,
    endHoldSeconds: 0.18,
    writingSoundEnabled: true,
    writingSoundPreset: preset,
    writingSoundVolume: volume.clamp(0.0, 1.0),
    strokes: [
      DrawingStroke(
        id: 'writing-sound-preview',
        name: 'Writing sound preview',
        points: [Offset(0.08, 0.52), Offset(0.92, 0.48)],
      ),
    ],
  );
}
