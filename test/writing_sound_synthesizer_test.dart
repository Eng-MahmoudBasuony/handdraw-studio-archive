import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_clip.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_library.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_synthesizer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const synthesizer = WritingSoundSynthesizer(sampleRate: 4000);

  HandDrawProject project({
    bool enabled = true,
    bool revealOnly = false,
    WritingSoundPreset preset = WritingSoundPreset.technicalPen,
  }) => HandDrawProject(
    durationSeconds: 2,
    frameRate: 30,
    startDelaySeconds: 0.4,
    endHoldSeconds: 0.4,
    writingSoundEnabled: enabled,
    writingSoundPreset: preset,
    writingSoundVolume: 0.8,
    strokes: [
      DrawingStroke(
        id: 'line',
        name: 'Line',
        revealOnly: revealOnly,
        points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
      ),
    ],
  );

  test('writes a valid mono PCM wave with the exact scene duration', () {
    final bytes = synthesizer.synthesize(project());
    final data = ByteData.sublistView(bytes);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 4000);
    expect(data.getUint32(40, Endian.little), 2 * 4000 * 2);
    expect(bytes.length, 44 + 2 * 4000 * 2);
  });

  test('is silent during waits and audible only while the pen is down', () {
    final samples = _samples(synthesizer.synthesize(project()));

    expect(_peak(samples, 0, 1200), 0, reason: 'Start wait must be silent.');
    expect(
      _peak(samples, 2400, 5600),
      greaterThan(500),
      reason: 'The writing interval must contain natural pen texture.',
    );
    expect(
      _peak(samples, 7000, 8000),
      0,
      reason: 'Final reading hold must be silent.',
    );
  });

  test('reveal-only animation and disabled audio stay silent', () {
    expect(_peak(_samples(synthesizer.synthesize(project(enabled: false)))), 0);
    expect(
      _peak(_samples(synthesizer.synthesize(project(revealOnly: true)))),
      0,
    );
  });

  test('the procedural sound presets produce different paper textures', () {
    final signatures = <int>{};
    for (final preset in WritingSoundPreset.values.where(
      (preset) => !preset.isRecorded,
    )) {
      final samples = _samples(synthesizer.synthesize(project(preset: preset)));
      signatures.add(
        samples
            .skip(2500)
            .take(1200)
            .fold<int>(0, (hash, sample) => (hash * 31 + sample) & 0x7FFFFFFF),
      );
    }
    expect(signatures, hasLength(3));
  });

  test('recorded texture follows the same pen-down timing envelope', () {
    final sourceWave = synthesizer.synthesize(
      project(preset: WritingSoundPreset.pencil),
    );
    final clip = WritingSoundClip.fromWave(sourceWave);
    final samples = _samples(
      synthesizer.synthesize(
        project(preset: WritingSoundPreset.recordedSoftPaper),
        recordedClip: clip,
      ),
    );

    expect(_peak(samples, 0, 1200), 0);
    expect(_peak(samples, 2400, 5600), greaterThan(500));
    expect(_peak(samples, 7000, 8000), 0);
  });

  test('all recorded sounds are packaged as valid PCM clips', () async {
    for (final preset in WritingSoundPreset.values.where(
      (preset) => preset.isRecorded,
    )) {
      final clip = await WritingSoundLibrary.load(preset);
      expect(clip, isNotNull, reason: preset.label);
      expect(clip!.sampleRate, 48000, reason: preset.label);
      expect(clip.samples.length, greaterThan(48000), reason: preset.label);
      final rendered = _samples(
        synthesizer.synthesize(project(preset: preset), recordedClip: clip),
      );
      expect(_peak(rendered, 0, 1200), 0, reason: preset.label);
      expect(
        _peak(rendered, 2400, 5600),
        greaterThan(100),
        reason: preset.label,
      );
      expect(_peak(rendered, 7000, 8000), 0, reason: preset.label);
    }
  });

  test('advanced pause extends audio and stays silent while hand holds', () {
    final pausedProject = project().copyWith(
      sectionTimings: const {
        'stroke:line': SectionTiming(pauseAfterSeconds: 0.5),
      },
    );
    final bytes = synthesizer.synthesize(pausedProject);
    final samples = _samples(bytes);

    expect(samples.length, 10000, reason: '2.0s base + 0.5s pause');
    expect(_peak(samples, 6800, 8000), 0);
  });

  test('in-stroke pause silences writing audio until drawing resumes', () {
    final pausedProject = HandDrawProject(
      durationSeconds: 3,
      drawingDurationSeconds: 3,
      frameRate: 30,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      writingSoundEnabled: true,
      writingSoundPreset: WritingSoundPreset.technicalPen,
      writingSoundVolume: 0.8,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
          pausePoints: const [
            StrokePausePoint(id: 'middle', progress: 0.5, durationSeconds: 1),
          ],
        ),
      ],
    );

    final samples = _samples(synthesizer.synthesize(pausedProject));

    expect(samples.length, 16000, reason: '3.0s drawing + 1.0s pause');
    expect(_peak(samples, 400, 5600), greaterThan(500));
    expect(
      _peak(samples, 6200, 9800),
      0,
      reason: 'The middle of the path hold must be completely silent.',
    );
    expect(_peak(samples, 10400, 15600), greaterThan(500));
  });
}

Int16List _samples(Uint8List wave) {
  final data = ByteData.sublistView(wave);
  final count = (wave.length - 44) ~/ 2;
  final samples = Int16List(count);
  for (var index = 0; index < count; index++) {
    samples[index] = data.getInt16(44 + index * 2, Endian.little);
  }
  return samples;
}

int _peak(Int16List samples, [int start = 0, int? end]) {
  var peak = 0;
  for (var index = start; index < (end ?? samples.length); index++) {
    final value = samples[index].abs();
    if (value > peak) peak = value;
  }
  return peak;
}
