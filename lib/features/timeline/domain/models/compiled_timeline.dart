import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/camera/domain/models/compiled_camera_track.dart';

final class TimelineDependencyKey {
  const TimelineDependencyKey({
    required this.projectId,
    required this.documentRevision,
  });

  final ProjectId projectId;
  final int documentRevision;

  @override
  bool operator ==(Object other) =>
      other is TimelineDependencyKey &&
      other.projectId == projectId &&
      other.documentRevision == documentRevision;

  @override
  int get hashCode => Object.hash(projectId, documentRevision);
}

final class TimelineInterval {
  factory TimelineInterval({
    required TimelineTime start,
    required TimelineTime end,
    String intervalType = 'unknown',
    String? entityId,
    String sourceOperation = 'unknown',
    int? documentRevision,
  }) {
    if (start.microseconds > end.microseconds) {
      throw InvalidTimelineIntervalException(
        intervalType: intervalType,
        entityId: entityId,
        start: start,
        end: end,
        sourceOperation: sourceOperation,
        documentRevision: documentRevision,
      );
    }
    return TimelineInterval._(start: start, end: end);
  }

  const TimelineInterval._({required this.start, required this.end});

  final TimelineTime start;
  final TimelineTime end;

  TimelineDuration get duration => end.difference(start);
  bool get isEmpty => start == end;

  /// Intervals are canonical half-open ranges: [start, end).
  bool contains(TimelineTime time) =>
      time.compareTo(start) >= 0 && time.compareTo(end) < 0;
}

final class InvalidTimelineIntervalException implements Exception {
  const InvalidTimelineIntervalException({
    required this.intervalType,
    required this.entityId,
    required this.start,
    required this.end,
    required this.sourceOperation,
    required this.documentRevision,
  });

  final String intervalType;
  final String? entityId;
  final TimelineTime start;
  final TimelineTime end;
  final String sourceOperation;
  final int? documentRevision;

  int get attemptedDurationMicroseconds =>
      end.microseconds - start.microseconds;

  @override
  String toString() =>
      'InvalidTimelineIntervalException('
      'type=$intervalType, entity=$entityId, start=${start.microseconds}, '
      'end=${end.microseconds}, duration=$attemptedDurationMicroseconds, '
      'source=$sourceOperation, '
      'revision=$documentRevision)';
}

final class CompiledDrawingSection {
  const CompiledDrawingSection({
    required this.sectionId,
    required this.interval,
  });

  final SectionId sectionId;
  final TimelineInterval interval;
}

final class CompiledDrawingTimelineTrack {
  CompiledDrawingTimelineTrack({
    required this.interval,
    required List<CompiledDrawingSection> sections,
  }) : sections = List.unmodifiable(sections);

  final TimelineInterval interval;
  final List<CompiledDrawingSection> sections;
}

final class CompiledAudioTimelineTrack {
  const CompiledAudioTimelineTrack({
    required this.audioTrackId,
    required this.assetId,
    required this.interval,
    required this.sourceOffset,
    required this.affectsTimelineDuration,
    required this.referenceOnly,
    required this.muted,
  });

  final AudioTrackId audioTrackId;
  final ProjectAssetId assetId;
  final TimelineInterval interval;
  final TimelineTime sourceOffset;
  final bool affectsTimelineDuration;
  final bool referenceOnly;
  final bool muted;
}

final class CompiledVoiceGuideTimelineTrack {
  const CompiledVoiceGuideTimelineTrack({
    required this.audioTrackId,
    required this.assetId,
    required this.interval,
    required this.sourceOffset,
    required this.affectsTimelineDuration,
    required this.referenceOnly,
    required this.muted,
  });

  final AudioTrackId audioTrackId;
  final ProjectAssetId assetId;
  final TimelineInterval interval;
  final TimelineTime sourceOffset;
  final bool affectsTimelineDuration;
  final bool referenceOnly;
  final bool muted;
}

final class CompiledSceneMarker {
  const CompiledSceneMarker({required this.sceneId, required this.time});

  final SceneId sceneId;
  final TimelineTime time;
}

final class CompiledTimeline {
  CompiledTimeline({
    required this.dependencyKey,
    required this.duration,
    required this.contentEnd,
    required this.drawing,
    this.camera,
    required List<CompiledAudioTimelineTrack> audio,
    required this.voiceGuide,
    required List<CompiledSceneMarker> sceneMarkers,
  }) : audio = List.unmodifiable(audio),
       sceneMarkers = List.unmodifiable(sceneMarkers);

  final TimelineDependencyKey dependencyKey;
  final TimelineDuration duration;
  final TimelineTime contentEnd;
  final CompiledDrawingTimelineTrack? drawing;
  final CompiledCameraTrack? camera;
  final List<CompiledAudioTimelineTrack> audio;
  final CompiledVoiceGuideTimelineTrack? voiceGuide;
  final List<CompiledSceneMarker> sceneMarkers;
}
