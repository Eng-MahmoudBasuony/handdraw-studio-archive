import 'dart:math' as math;

class VideoExportInspection {
  const VideoExportInspection({
    required this.codec,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.durationSeconds,
    required this.hasAlpha,
    required this.orientationDegrees,
    required this.hasAudio,
    this.audioDurationSeconds,
  });

  factory VideoExportInspection.fromMap(Map<Object?, Object?> map) =>
      VideoExportInspection(
        codec: map['codec']! as String,
        width: (map['width']! as num).round(),
        height: (map['height']! as num).round(),
        frameRate: (map['frameRate']! as num).toDouble(),
        durationSeconds: (map['durationSeconds']! as num).toDouble(),
        hasAlpha: map['hasAlpha']! as bool,
        orientationDegrees: (map['orientationDegrees']! as num).round(),
        hasAudio: map['hasAudio'] as bool? ?? false,
        audioDurationSeconds: (map['audioDurationSeconds'] as num?)?.toDouble(),
      );

  final String codec;
  final int width;
  final int height;
  final double frameRate;
  final double durationSeconds;
  final bool hasAlpha;
  final int orientationDegrees;
  final bool hasAudio;
  final double? audioDurationSeconds;
}

class VideoExportContract {
  const VideoExportContract({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.durationSeconds,
    this.requiresAlpha = true,
    this.expectsAudio = false,
  });

  final int width;
  final int height;
  final int frameRate;
  final double durationSeconds;
  final bool requiresAlpha;
  final bool expectsAudio;

  List<String> validate(VideoExportInspection inspection) {
    final errors = <String>[];
    final codec = inspection.codec.toLowerCase();
    if (!const {'ap4h', 'ap4x', 'prores4444'}.contains(codec)) {
      errors.add('Expected Apple ProRes 4444, found ${inspection.codec}.');
    }
    if (inspection.width != width || inspection.height != height) {
      errors.add(
        'Expected $width×$height, found '
        '${inspection.width}×${inspection.height}.',
      );
    }
    if ((inspection.frameRate - frameRate).abs() > 0.05) {
      errors.add('Expected $frameRate fps, found ${inspection.frameRate}.');
    }
    final frameTolerance = 1 / math.max(1, frameRate) + 0.002;
    if ((inspection.durationSeconds - durationSeconds).abs() > frameTolerance) {
      errors.add(
        'Expected ${durationSeconds.toStringAsFixed(3)} s, found '
        '${inspection.durationSeconds.toStringAsFixed(3)} s.',
      );
    }
    if (requiresAlpha && !inspection.hasAlpha) {
      errors.add('The movie does not expose a ProRes alpha channel.');
    }
    if (inspection.orientationDegrees % 360 != 0) {
      errors.add('The movie orientation is not upright.');
    }
    if (expectsAudio) {
      if (!inspection.hasAudio) {
        errors.add('The movie is missing its synchronized audio track.');
      }
      final audio = inspection.audioDurationSeconds;
      if (audio != null &&
          (audio - inspection.durationSeconds).abs() > frameTolerance) {
        errors.add(
          'Audio and video differ by more than one frame '
          '(${audio.toStringAsFixed(3)} s vs '
          '${inspection.durationSeconds.toStringAsFixed(3)} s).',
        );
      }
    }
    return List.unmodifiable(errors);
  }
}
