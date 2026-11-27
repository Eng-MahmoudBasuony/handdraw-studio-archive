import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum SimpleCameraMovement { cut, linear, ease }

/// Maps the simple one-view UI onto the existing shot/keyframe schema.
final class SimpleCameraViewAdapter {
  const SimpleCameraViewAdapter();

  CameraTransition transitionFor(
    SimpleCameraMovement movement,
    TimelineDuration duration,
  ) => switch (movement) {
    SimpleCameraMovement.cut => const CameraTransition(),
    SimpleCameraMovement.linear => CameraTransition(
      type: CameraTransitionType.move,
      duration: duration,
      easing: CameraEasing.linear,
    ),
    SimpleCameraMovement.ease => CameraTransition(
      type: CameraTransitionType.move,
      duration: duration,
      easing: CameraEasing.easeInOut,
    ),
  };

  TimelineDuration totalDuration({
    required SimpleCameraMovement movement,
    required TimelineDuration movementDuration,
    required TimelineDuration holdDuration,
  }) => TimelineDuration.fromMicroseconds(
    holdDuration.microseconds +
        (movement == SimpleCameraMovement.cut
            ? 0
            : movementDuration.microseconds),
  );
}
