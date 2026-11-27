import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_clip.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_resolved_drawing_frame_adapter.dart';

class WritingSoundSynthesizer {
  const WritingSoundSynthesizer({this.sampleRate = 48000});

  final int sampleRate;

  Uint8List synthesize(
    HandDrawProject project, {
    WritingSoundClip? recordedClip,
    CompiledTimeline? timeline,
  }) {
    final resolvedDurationSeconds = timeline == null
        ? projectTimelineDuration(project)
        : timeline.duration.microseconds / Duration.microsecondsPerSecond;
    final sampleCount = math.max(
      1,
      (resolvedDurationSeconds * sampleRate).round(),
    );
    final pcm = Int16List(sampleCount);
    if (!project.writingSoundEnabled || project.strokes.isEmpty) {
      return _encodeWave(pcm);
    }

    final artworkRect = Rect.fromLTWH(
      0,
      0,
      project.canvasWidth.toDouble(),
      project.canvasHeight.toDouble(),
    );
    final frameRate = FrameRate(numerator: project.frameRate.round());
    final controlFrameCount = timeline == null
        ? math.max(2, (resolvedDurationSeconds * project.frameRate).round())
        : const FrameSamplingPolicy().frameCount(
            duration: timeline.duration,
            frameRate: frameRate,
          );
    final visible = List<bool>.filled(controlFrameCount, false);
    final energy = List<double>.filled(controlFrameCount, 0);
    Offset? previousPosition;
    var previousVisible = false;
    final diagonal = math.max(1.0, artworkRect.size.longestSide);

    for (var frame = 0; frame < controlFrameCount; frame++) {
      late final TimelineSnapshot snapshot;
      if (timeline == null) {
        snapshot = buildTimelineSnapshot(
          strokes: project.strokes,
          artworkRect: artworkRect,
          progress: frame / (controlFrameCount - 1),
          durationSeconds: project.durationSeconds,
          drawingDurationSeconds: project.drawingDurationSeconds,
          drawingSpeed: project.drawingSpeed,
          penTravelSpeed: project.penTravelSpeed,
          startDelaySeconds: project.startDelaySeconds,
          endHoldSeconds: project.endHoldSeconds,
          sectionTimings: project.sectionTimings,
          timingRect: artworkRect,
        );
      } else {
        final resolved = const GlobalTimelineResolver().resolveAt(
          timeline,
          const FrameSamplingPolicy().timeForFrame(
            index: frame,
            duration: timeline.duration,
            frameRate: frameRate,
          ),
        );
        final drawing = resolved.drawing;
        snapshot = drawing == null
            ? const TimelineSnapshot(
                revealedPaths: [],
                handPosition: Offset.zero,
                handAngle: 0,
                handVisible: false,
                phase: TimelinePhase.startDelay,
              )
            : const LegacyResolvedDrawingFrameAdapter().resolve(
                project: project,
                frame: drawing,
                artworkRect: artworkRect,
                timingRect: artworkRect,
              );
      }
      final penIsWriting = snapshot.penIsDrawing;
      visible[frame] = penIsWriting;
      if (penIsWriting) {
        final distance = previousVisible && previousPosition != null
            ? (snapshot.handPosition - previousPosition).distance / diagonal
            : 0.004;
        energy[frame] = (0.42 + distance * project.frameRate * 5.5).clamp(
          0.35,
          1.0,
        );
      }
      previousPosition = snapshot.handPosition;
      previousVisible = penIsWriting;
    }

    var seed = 0x5EED1234;
    var lowPass = 0.0;
    var slowerPass = 0.0;
    var envelope = 0.0;
    var recordedCursor = 0.0;
    final volume = project.writingSoundVolume.clamp(0.0, 1.0);
    final attack = 1 - math.exp(-1 / (sampleRate * 0.004));
    final release = 1 - math.exp(-1 / (sampleRate * 0.012));

    for (var sample = 0; sample < sampleCount; sample++) {
      final framePosition =
          sample / math.max(1, sampleCount - 1) * (controlFrameCount - 1);
      final frame = framePosition.floor().clamp(0, controlFrameCount - 1);
      final nextFrame = math.min(frame + 1, controlFrameCount - 1);
      final fraction = framePosition - frame;
      final isWriting = visible[frame] || visible[nextFrame];
      final targetEnvelope = isWriting ? 1.0 : 0.0;
      envelope +=
          (targetEnvelope - envelope) *
          (targetEnvelope > envelope ? attack : release);
      if (envelope < 0.0001 && !isWriting) continue;

      seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF;
      final noise = ((seed / 0xFFFFFFFF) * 2) - 1;
      lowPass += (noise - lowPass) * 0.18;
      slowerPass += (noise - slowerPass) * 0.035;
      final highPass = noise - lowPass;
      final motionEnergy =
          energy[frame] + (energy[nextFrame] - energy[frame]) * fraction;
      final double texture;
      final double level;
      if (recordedClip != null) {
        texture = recordedClip.sampleAt(recordedCursor);
        if (isWriting || envelope > 0.0001) {
          recordedCursor += recordedClip.sampleRate / sampleRate;
        }
        level = 0.68 + motionEnergy * 0.42;
      } else {
        texture = _textureFor(
          project.writingSoundPreset,
          noise: noise,
          lowPass: lowPass,
          slowerPass: slowerPass,
          highPass: highPass,
          sample: sample,
        );
        level = motionEnergy * 0.34;
      }
      final amplitude = texture * envelope * level * volume;
      pcm[sample] = (amplitude.clamp(-1.0, 1.0) * 32767).round();
    }
    return _encodeWave(pcm);
  }

  double _textureFor(
    WritingSoundPreset preset, {
    required double noise,
    required double lowPass,
    required double slowerPass,
    required double highPass,
    required int sample,
  }) => switch (preset) {
    WritingSoundPreset.pencil =>
      highPass * 0.78 + lowPass * 0.20 + math.sin(sample * 0.071) * 0.025,
    WritingSoundPreset.marker =>
      slowerPass * 1.15 + lowPass * 0.48 + math.sin(sample * 0.018) * 0.035,
    WritingSoundPreset.technicalPen =>
      highPass * 0.46 +
          lowPass * 0.38 +
          noise * 0.10 +
          math.sin(sample * 0.049) * 0.018,
    WritingSoundPreset.recordedSoftPaper ||
    WritingSoundPreset.recordedPencilPaper ||
    WritingSoundPreset.recordedNaturalPaper ||
    WritingSoundPreset.recordedQuickPaper =>
      highPass * 0.46 + lowPass * 0.38 + noise * 0.10,
  };

  Uint8List _encodeWave(Int16List samples) {
    const channels = 1;
    const bitsPerSample = 16;
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      bytes.setInt16(44 + index * 2, samples[index], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
