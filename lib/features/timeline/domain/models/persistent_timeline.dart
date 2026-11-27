import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class PersistentDrawingTimelineTrack {
  const PersistentDrawingTimelineTrack({this.enabled = true});

  final bool enabled;
}

/// Reserved persistent contract for a future camera track.
///
/// Step 4A deliberately stores no keyframes, transforms, or camera behavior.
final class PersistentCameraTimelineTrack {
  const PersistentCameraTimelineTrack.disabled()
    : enabled = false,
      cameraTrackId = null;
  const PersistentCameraTimelineTrack.enabled({required this.cameraTrackId})
    : enabled = true;

  final bool enabled;
  final CameraTrackId? cameraTrackId;
}

final class PersistentAudioTimelineTrack {
  const PersistentAudioTimelineTrack({required this.audioTrackId});

  final AudioTrackId audioTrackId;
}

final class PersistentVoiceGuideTimelineTrack {
  const PersistentVoiceGuideTimelineTrack({required this.audioTrackId});

  final AudioTrackId audioTrackId;
}

final class PersistentSceneMarker {
  const PersistentSceneMarker({required this.sceneId, required this.time});

  final SceneId sceneId;
  final TimelineTime time;
}

/// Project-owned global timeline configuration.
///
/// Authored section timing remains on ProjectSection and audio placement stays
/// on ProjectAudioTrack. This aggregate references those typed sources instead
/// of duplicating their timing values.
final class PersistentTimeline {
  PersistentTimeline({
    this.drawing = const PersistentDrawingTimelineTrack(),
    this.camera = const PersistentCameraTimelineTrack.disabled(),
    List<PersistentAudioTimelineTrack> audio = const [],
    this.voiceGuide,
    List<PersistentSceneMarker> sceneMarkers = const [],
    this.leadingHold = TimelineDuration.zero,
    this.trailingHold = TimelineDuration.zero,
  }) : audio = List.unmodifiable(audio),
       sceneMarkers = List.unmodifiable(sceneMarkers);

  final PersistentDrawingTimelineTrack drawing;
  final PersistentCameraTimelineTrack camera;
  final List<PersistentAudioTimelineTrack> audio;
  final PersistentVoiceGuideTimelineTrack? voiceGuide;
  final List<PersistentSceneMarker> sceneMarkers;
  final TimelineDuration leadingHold;
  final TimelineDuration trailingHold;

  PersistentTimeline copyWith({PersistentCameraTimelineTrack? camera}) =>
      PersistentTimeline(
        drawing: drawing,
        camera: camera ?? this.camera,
        audio: audio,
        voiceGuide: voiceGuide,
        sceneMarkers: sceneMarkers,
        leadingHold: leadingHold,
        trailingHold: trailingHold,
      );
}
