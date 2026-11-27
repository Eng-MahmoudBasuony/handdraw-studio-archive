import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraZoomPresetIds {
  CameraZoomPresetIds({
    required List<CameraShotId> shots,
    required List<CameraKeyframeId> keyframes,
  }) : shots = List.unmodifiable(shots),
       keyframes = List.unmodifiable(keyframes);

  final List<CameraShotId> shots;
  final List<CameraKeyframeId> keyframes;
}

final class CameraZoomInOutPlan {
  CameraZoomInOutPlan({
    required List<CameraShot> shots,
    required this.closeView,
  }) : shots = List.unmodifiable(shots);

  final List<CameraShot> shots;
  final CameraView closeView;
}

/// Builds a simple Wide -> Close -> Wide sequence spanning one authored shot.
final class CameraZoomInOutPresetPlanner {
  const CameraZoomInOutPresetPlanner();

  static final edgeHoldDuration = TimelineDuration.fromDuration(
    const Duration(milliseconds: 100),
  );
  static final minimumCloseHoldDuration = TimelineDuration.fromDuration(
    const Duration(milliseconds: 100),
  );
  static final minimumMovementDuration = TimelineDuration.fromDuration(
    const Duration(milliseconds: 200),
  );
  static TimelineDuration get minimumTotalDuration =>
      TimelineDuration.fromMicroseconds(
        edgeHoldDuration.microseconds * 2 +
            minimumCloseHoldDuration.microseconds +
            minimumMovementDuration.microseconds * 2,
      );

  CameraZoomInOutPlan? build({
    required TimelineTime startTime,
    required TimelineDuration totalDuration,
    required CameraView wideView,
    required CameraView focusView,
    required double strength,
    required TimelineDuration zoomInDuration,
    required TimelineDuration zoomOutDuration,
    required CameraZoomPresetIds ids,
    String wideLabel = 'Wide',
    String zoomInLabel = 'Zoom In',
    String zoomOutLabel = 'Zoom Out',
  }) {
    if (!strength.isFinite ||
        strength <= 1 ||
        zoomInDuration.microseconds < minimumMovementDuration.microseconds ||
        zoomOutDuration.microseconds < minimumMovementDuration.microseconds ||
        ids.shots.length != 3 ||
        ids.keyframes.length != 5) {
      return null;
    }
    final fixedUs =
        edgeHoldDuration.microseconds * 2 +
        minimumCloseHoldDuration.microseconds +
        zoomInDuration.microseconds +
        zoomOutDuration.microseconds;
    if (totalDuration.microseconds < fixedUs) return null;

    final closeHold = TimelineDuration.fromMicroseconds(
      totalDuration.microseconds -
          edgeHoldDuration.microseconds * 2 -
          zoomInDuration.microseconds -
          zoomOutDuration.microseconds,
    );
    final closeView = CameraView(
      centerX: focusView.centerX,
      centerY: focusView.centerY,
      viewportWidth: wideView.viewportWidth / strength,
    );
    final closeStart = startTime + edgeHoldDuration;
    final closeDuration = TimelineDuration.fromMicroseconds(
      zoomInDuration.microseconds + closeHold.microseconds,
    );
    final outStart = closeStart + closeDuration;
    final outDuration = TimelineDuration.fromMicroseconds(
      zoomOutDuration.microseconds + edgeHoldDuration.microseconds,
    );
    final easeInOut = CameraTransition(
      type: CameraTransitionType.move,
      duration: zoomInDuration,
      easing: CameraEasing.easeInOut,
    );
    final easeOut = CameraTransition(
      type: CameraTransitionType.move,
      duration: zoomOutDuration,
      easing: CameraEasing.easeInOut,
    );

    return CameraZoomInOutPlan(
      closeView: closeView,
      shots: [
        CameraShot(
          id: ids.shots[0],
          startTime: startTime,
          duration: edgeHoldDuration,
          authorship: CameraAuthorship.manual,
          isLocked: false,
          label: wideLabel,
          keyframes: [
            CameraKeyframe(
              id: ids.keyframes[0],
              offset: TimelineTime.zero,
              view: wideView,
            ),
          ],
        ),
        CameraShot(
          id: ids.shots[1],
          startTime: closeStart,
          duration: closeDuration,
          authorship: CameraAuthorship.manual,
          isLocked: false,
          label: zoomInLabel,
          keyframes: [
            CameraKeyframe(
              id: ids.keyframes[1],
              offset: TimelineTime.zero,
              view: closeView,
            ),
            CameraKeyframe(
              id: ids.keyframes[2],
              offset: TimelineTime.fromMicroseconds(
                zoomInDuration.microseconds,
              ),
              view: closeView,
              incomingTransition: easeInOut,
            ),
          ],
        ),
        CameraShot(
          id: ids.shots[2],
          startTime: outStart,
          duration: outDuration,
          authorship: CameraAuthorship.manual,
          isLocked: false,
          label: zoomOutLabel,
          keyframes: [
            CameraKeyframe(
              id: ids.keyframes[3],
              offset: TimelineTime.zero,
              view: wideView,
            ),
            CameraKeyframe(
              id: ids.keyframes[4],
              offset: TimelineTime.fromMicroseconds(
                zoomOutDuration.microseconds,
              ),
              view: wideView,
              incomingTransition: easeOut,
            ),
          ],
        ),
      ],
    );
  }
}
