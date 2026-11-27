import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum CameraAuthorship { auto, manual }

enum CameraTransitionType { cut, move, fade }

enum CameraEasing { linear, easeIn, easeOut, easeInOut }

/// Defines how a scene-owned camera clip meets the camera clip before it.
enum CameraSceneConnection { continuePrevious, cut, transition }

final class CameraView {
  const CameraView({
    required this.centerX,
    required this.centerY,
    required this.viewportWidth,
  });
  const CameraView.identity() : centerX = .5, centerY = .5, viewportWidth = 1;
  final double centerX;
  final double centerY;
  final double viewportWidth;

  /// Height in project-normalized Y units. X and Y are normalized against
  /// their own project dimensions, so converting a width to a height must
  /// account for both project and output aspect ratios.
  double normalizedViewportHeightFor({
    required double projectAspectRatio,
    required double outputAspectRatio,
  }) => viewportWidth * projectAspectRatio / outputAspectRatio;

  /// Legacy width-normalized height. Prefer [normalizedViewportHeightFor]
  /// whenever the result is used with `centerY` or project-normalized Y.
  double viewportHeightFor(double aspectRatio) => viewportWidth / aspectRatio;
  @override
  bool operator ==(Object other) =>
      other is CameraView &&
      centerX == other.centerX &&
      centerY == other.centerY &&
      viewportWidth == other.viewportWidth;
  @override
  int get hashCode => Object.hash(centerX, centerY, viewportWidth);
}

final class CameraTransition {
  const CameraTransition({
    this.type = CameraTransitionType.cut,
    this.duration = TimelineDuration.zero,
    this.easing = CameraEasing.linear,
  });
  final CameraTransitionType type;
  final TimelineDuration duration;
  final CameraEasing easing;
  CameraTransition copyWith({
    CameraTransitionType? type,
    TimelineDuration? duration,
    CameraEasing? easing,
  }) => CameraTransition(
    type: type ?? this.type,
    duration: duration ?? this.duration,
    easing: easing ?? this.easing,
  );
  @override
  bool operator ==(Object other) =>
      other is CameraTransition &&
      type == other.type &&
      duration == other.duration &&
      easing == other.easing;
  @override
  int get hashCode => Object.hash(type, duration, easing);
}

final class CameraKeyframe {
  const CameraKeyframe({
    required this.id,
    required this.offset,
    required this.view,
    this.incomingTransition = const CameraTransition(),
  });
  final CameraKeyframeId id;
  final TimelineTime offset;
  final CameraView view;
  final CameraTransition incomingTransition;
  CameraKeyframe copyWith({
    TimelineTime? offset,
    CameraView? view,
    CameraTransition? incomingTransition,
  }) => CameraKeyframe(
    id: id,
    offset: offset ?? this.offset,
    view: view ?? this.view,
    incomingTransition: incomingTransition ?? this.incomingTransition,
  );
  @override
  bool operator ==(Object other) =>
      other is CameraKeyframe &&
      id == other.id &&
      offset == other.offset &&
      view == other.view &&
      incomingTransition == other.incomingTransition;
  @override
  int get hashCode => Object.hash(id, offset, view, incomingTransition);
}

final class CameraShot {
  CameraShot({
    required this.id,
    required this.startTime,
    required this.duration,
    required this.authorship,
    required this.isLocked,
    this.label,
    this.ownerSceneId,
    this.sceneConnection = CameraSceneConnection.cut,
    required List<CameraKeyframe> keyframes,
  }) : keyframes = List.unmodifiable(keyframes);
  final CameraShotId id;
  final TimelineTime startTime;
  final TimelineDuration duration;
  final CameraAuthorship authorship;
  final bool isLocked;
  final String? label;
  final SceneId? ownerSceneId;
  final CameraSceneConnection sceneConnection;
  final List<CameraKeyframe> keyframes;
  TimelineTime get endTime => startTime + duration;
  CameraShot copyWith({
    TimelineTime? startTime,
    TimelineDuration? duration,
    CameraAuthorship? authorship,
    bool? isLocked,
    Object? label = _unset,
    Object? ownerSceneId = _unset,
    CameraSceneConnection? sceneConnection,
    List<CameraKeyframe>? keyframes,
  }) => CameraShot(
    id: id,
    startTime: startTime ?? this.startTime,
    duration: duration ?? this.duration,
    authorship: authorship ?? this.authorship,
    isLocked: isLocked ?? this.isLocked,
    label: identical(label, _unset) ? this.label : label as String?,
    ownerSceneId: identical(ownerSceneId, _unset)
        ? this.ownerSceneId
        : ownerSceneId as SceneId?,
    sceneConnection: sceneConnection ?? this.sceneConnection,
    keyframes: keyframes ?? this.keyframes,
  );
  @override
  bool operator ==(Object other) =>
      other is CameraShot &&
      id == other.id &&
      startTime == other.startTime &&
      duration == other.duration &&
      authorship == other.authorship &&
      isLocked == other.isLocked &&
      label == other.label &&
      ownerSceneId == other.ownerSceneId &&
      sceneConnection == other.sceneConnection &&
      _listEquals(keyframes, other.keyframes);
  @override
  int get hashCode => Object.hash(
    id,
    startTime,
    duration,
    authorship,
    isLocked,
    label,
    ownerSceneId,
    sceneConnection,
    Object.hashAll(keyframes),
  );
}

final class ProjectCameraTrack {
  ProjectCameraTrack({
    required this.id,
    this.enabled = true,
    this.defaultView = const CameraView.identity(),
    required List<CameraShot> shots,
  }) : shots = List.unmodifiable(shots);
  final CameraTrackId id;
  final bool enabled;
  final CameraView defaultView;
  final List<CameraShot> shots;
  ProjectCameraTrack copyWith({
    bool? enabled,
    CameraView? defaultView,
    List<CameraShot>? shots,
  }) => ProjectCameraTrack(
    id: id,
    enabled: enabled ?? this.enabled,
    defaultView: defaultView ?? this.defaultView,
    shots: shots ?? this.shots,
  );
  @override
  bool operator ==(Object other) =>
      other is ProjectCameraTrack &&
      id == other.id &&
      enabled == other.enabled &&
      defaultView == other.defaultView &&
      _listEquals(shots, other.shots);
  @override
  int get hashCode =>
      Object.hash(id, enabled, defaultView, Object.hashAll(shots));
}

bool _listEquals(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _unset = Object();
