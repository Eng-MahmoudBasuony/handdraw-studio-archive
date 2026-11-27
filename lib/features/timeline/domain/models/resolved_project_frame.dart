import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';

final class ResolvedDrawingFrame {
  const ResolvedDrawingFrame({
    required this.localTime,
    required this.duration,
    required this.sectionId,
    required this.isHeld,
  });

  final TimelineTime localTime;
  final TimelineDuration duration;
  final SectionId? sectionId;
  final bool isHeld;
}

final class ResolvedAudioFrame {
  const ResolvedAudioFrame({
    required this.audioTrackId,
    required this.sourceTime,
  });

  final AudioTrackId audioTrackId;
  final TimelineTime sourceTime;
}

final class ResolvedVoiceGuideFrame {
  const ResolvedVoiceGuideFrame({
    required this.audioTrackId,
    required this.sourceTime,
  });

  final AudioTrackId audioTrackId;
  final TimelineTime sourceTime;
}

final class ResolvedProjectFrame {
  ResolvedProjectFrame({
    required this.time,
    required this.drawing,
    required this.camera,
    required List<ResolvedAudioFrame> activeAudio,
    required this.voiceGuide,
    required List<SceneId> markers,
    required this.isFinalFrame,
  }) : activeAudio = List.unmodifiable(activeAudio),
       markers = List.unmodifiable(markers);

  final TimelineTime time;
  final ResolvedDrawingFrame? drawing;
  final ResolvedCameraState camera;
  final List<ResolvedAudioFrame> activeAudio;
  final ResolvedVoiceGuideFrame? voiceGuide;
  final List<SceneId> markers;
  final bool isFinalFrame;
}
