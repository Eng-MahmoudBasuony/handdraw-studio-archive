import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_resolver.dart';

final class GlobalTimelineResolver {
  const GlobalTimelineResolver();

  ResolvedProjectFrame resolveAt(CompiledTimeline timeline, TimelineTime time) {
    final resolvedTime = time.clampTo(timeline.duration);
    final drawing = timeline.drawing;
    ResolvedDrawingFrame? drawingFrame;
    if (drawing != null &&
        resolvedTime.compareTo(drawing.interval.start) >= 0) {
      final held = resolvedTime.compareTo(drawing.interval.end) >= 0;
      final localUs = held
          ? drawing.interval.duration.microseconds
          : resolvedTime.difference(drawing.interval.start).microseconds;
      drawingFrame = ResolvedDrawingFrame(
        localTime: TimelineTime.fromMicroseconds(localUs),
        duration: drawing.interval.duration,
        sectionId: held
            ? drawing.sections.lastOrNull?.sectionId
            : _sectionAt(drawing, resolvedTime),
        isHeld: held,
      );
    }
    final voice = timeline.voiceGuide;
    final resolvedVoice =
        voice != null && !voice.muted && voice.interval.contains(resolvedTime)
        ? ResolvedVoiceGuideFrame(
            audioTrackId: voice.audioTrackId,
            sourceTime: TimelineTime.fromMicroseconds(
              voice.sourceOffset.microseconds +
                  resolvedTime.difference(voice.interval.start).microseconds,
            ),
          )
        : null;
    return ResolvedProjectFrame(
      time: resolvedTime,
      drawing: drawingFrame,
      camera: timeline.camera == null
          ? const ResolvedSingleCameraView(CameraView.identity())
          : const CameraResolver().resolveAt(timeline.camera!, resolvedTime),
      activeAudio: [
        for (final track in timeline.audio)
          if (!track.muted && track.interval.contains(resolvedTime))
            ResolvedAudioFrame(
              audioTrackId: track.audioTrackId,
              sourceTime: TimelineTime.fromMicroseconds(
                track.sourceOffset.microseconds +
                    resolvedTime.difference(track.interval.start).microseconds,
              ),
            ),
      ],
      voiceGuide: resolvedVoice,
      markers: [
        for (final marker in timeline.sceneMarkers)
          if (marker.time == resolvedTime) marker.sceneId,
      ],
      isFinalFrame: resolvedTime.microseconds == timeline.duration.microseconds,
    );
  }

  SectionId? _sectionAt(
    CompiledDrawingTimelineTrack drawing,
    TimelineTime time,
  ) {
    var low = 0;
    var high = drawing.sections.length - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final section = drawing.sections[middle];
      if (time.compareTo(section.interval.start) < 0) {
        high = middle - 1;
      } else if (time.compareTo(section.interval.end) >= 0) {
        low = middle + 1;
      } else {
        return section.sectionId;
      }
    }
    return null;
  }
}
