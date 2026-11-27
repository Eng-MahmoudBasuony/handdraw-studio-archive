import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart'
    show TimelineDependencyKey, TimelineInterval;
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum CompiledCameraSegmentKind { hold, move, fade }

final class CompiledCameraSegment {
  const CompiledCameraSegment({
    required this.interval,
    required this.kind,
    required this.fromView,
    required this.toView,
    required this.easing,
  });
  final TimelineInterval interval;
  final CompiledCameraSegmentKind kind;
  final CameraView fromView;
  final CameraView toView;
  final CameraEasing easing;
}

final class CompiledCameraShot {
  CompiledCameraShot({
    required this.id,
    required this.interval,
    required this.startView,
    required this.finalView,
    required List<CompiledCameraSegment> segments,
  }) : segments = List.unmodifiable(segments);
  final CameraShotId id;
  final TimelineInterval interval;
  final CameraView startView;
  final CameraView finalView;
  final List<CompiledCameraSegment> segments;
}

final class CompiledCameraTrack {
  CompiledCameraTrack({
    required this.dependencyKey,
    required this.id,
    required this.enabled,
    required this.defaultView,
    required this.contentEnd,
    required List<CompiledCameraShot> shots,
  }) : shots = List.unmodifiable(shots);
  final TimelineDependencyKey dependencyKey;
  final CameraTrackId id;
  final bool enabled;
  final CameraView defaultView;
  final TimelineTime contentEnd;
  final List<CompiledCameraShot> shots;
}
