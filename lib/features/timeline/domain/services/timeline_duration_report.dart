import 'dart:math' as math;

import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class TimelineDurationReport {
  const TimelineDurationReport({
    required this.drawingEnd,
    required this.cameraEnd,
    required this.voiceGuideEnd,
    required this.includedAudioEnd,
    required this.explicitHoldEnd,
    required this.resolvedGlobalDuration,
  });

  final TimelineTime drawingEnd;
  final TimelineTime cameraEnd;
  final TimelineTime voiceGuideEnd;
  final TimelineTime includedAudioEnd;
  final TimelineTime explicitHoldEnd;
  final TimelineDuration resolvedGlobalDuration;

  static TimelineDurationReport fromCompiled(CompiledTimeline timeline) {
    final drawingUs = timeline.drawing?.interval.end.microseconds ?? 0;
    final cameraUs = timeline.camera?.contentEnd.microseconds ?? 0;
    final voiceUs = timeline.voiceGuide?.affectsTimelineDuration == true
        ? timeline.voiceGuide!.interval.end.microseconds
        : 0;
    final audioUs = timeline.audio
        .where((track) => track.affectsTimelineDuration)
        .fold<int>(
          0,
          (end, track) => math.max(end, track.interval.end.microseconds),
        );
    final contributorEnd = math.max(
      math.max(drawingUs, cameraUs),
      math.max(voiceUs, audioUs),
    );
    return TimelineDurationReport(
      drawingEnd: TimelineTime.fromMicroseconds(drawingUs),
      cameraEnd: TimelineTime.fromMicroseconds(cameraUs),
      voiceGuideEnd: TimelineTime.fromMicroseconds(voiceUs),
      includedAudioEnd: TimelineTime.fromMicroseconds(audioUs),
      explicitHoldEnd: TimelineTime.fromMicroseconds(
        timeline.duration.microseconds > contributorEnd
            ? timeline.duration.microseconds
            : 0,
      ),
      resolvedGlobalDuration: timeline.duration,
    );
  }
}
