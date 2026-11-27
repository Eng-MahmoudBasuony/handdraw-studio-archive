import 'package:handdraw_studio/features/camera/domain/models/compiled_camera_track.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraTimelineCompiler {
  const CameraTimelineCompiler();
  CompiledCameraTrack compile({
    required ProjectCameraTrack track,
    required TimelineDependencyKey dependencyKey,
    TimelineDuration offset = TimelineDuration.zero,
  }) {
    final shift = offset.microseconds;
    final shots = <CompiledCameraShot>[];
    CameraView? previousSimpleView;
    for (final shot in track.shots) {
      final shotStart = shift + shot.startTime.microseconds;
      final isSimpleViewShot =
          shot.keyframes.length == 1 ||
          (shot.keyframes.length == 2 &&
              shot.keyframes.first.view == shot.keyframes.last.view &&
              shot.keyframes.last.offset.microseconds ==
                  shot.keyframes.last.incomingTransition.duration.microseconds);
      if (isSimpleViewShot) {
        final target = shot.keyframes.last;
        final transition = target.incomingTransition;
        final sourceView = previousSimpleView;
        final canMoveFromPrevious =
            sourceView != null &&
            transition.type != CameraTransitionType.cut &&
            !transition.duration.isZero;
        final movementUs = canMoveFromPrevious
            ? transition.duration.microseconds.clamp(
                0,
                shot.duration.microseconds,
              )
            : 0;
        final arrival = shotStart + movementUs;
        final end = shotStart + shot.duration.microseconds;
        final segments = <CompiledCameraSegment>[];
        if (movementUs > 0) {
          segments.add(
            CompiledCameraSegment(
              interval: TimelineInterval(
                start: TimelineTime.fromMicroseconds(shotStart),
                end: TimelineTime.fromMicroseconds(arrival),
                intervalType: 'camera-transition',
                entityId: shot.id.value,
                sourceOperation: 'camera-simple-view-compile',
                documentRevision: dependencyKey.documentRevision,
              ),
              kind: transition.type == CameraTransitionType.fade
                  ? CompiledCameraSegmentKind.fade
                  : CompiledCameraSegmentKind.move,
              fromView: sourceView ?? target.view,
              toView: target.view,
              easing: transition.easing,
            ),
          );
        }
        if (arrival < end) {
          segments.add(
            CompiledCameraSegment(
              interval: TimelineInterval(
                start: TimelineTime.fromMicroseconds(arrival),
                end: TimelineTime.fromMicroseconds(end),
                intervalType: 'camera-hold',
                entityId: shot.id.value,
                sourceOperation: 'camera-simple-view-compile',
                documentRevision: dependencyKey.documentRevision,
              ),
              kind: CompiledCameraSegmentKind.hold,
              fromView: target.view,
              toView: target.view,
              easing: CameraEasing.linear,
            ),
          );
        }
        shots.add(
          CompiledCameraShot(
            id: shot.id,
            interval: TimelineInterval(
              start: TimelineTime.fromMicroseconds(shotStart),
              end: TimelineTime.fromMicroseconds(end),
              intervalType: 'camera-shot',
              entityId: shot.id.value,
              sourceOperation: 'camera-simple-view-compile',
              documentRevision: dependencyKey.documentRevision,
            ),
            startView: canMoveFromPrevious ? sourceView : target.view,
            finalView: target.view,
            segments: segments,
          ),
        );
        previousSimpleView = target.view;
        continue;
      }
      final segments = <CompiledCameraSegment>[];
      var previous = shot.keyframes.first;
      for (final target in shot.keyframes.skip(1)) {
        final arrival = shotStart + target.offset.microseconds;
        final transition = target.incomingTransition;
        final transitionStart = arrival - transition.duration.microseconds;
        final previousTime = shotStart + previous.offset.microseconds;
        if (transitionStart > previousTime) {
          segments.add(
            CompiledCameraSegment(
              interval: TimelineInterval(
                start: TimelineTime.fromMicroseconds(previousTime),
                end: TimelineTime.fromMicroseconds(transitionStart),
                intervalType: 'camera-hold',
                entityId: shot.id.value,
                sourceOperation: 'camera-timeline-compile',
                documentRevision: dependencyKey.documentRevision,
              ),
              kind: CompiledCameraSegmentKind.hold,
              fromView: previous.view,
              toView: previous.view,
              easing: CameraEasing.linear,
            ),
          );
        }
        if (!transition.duration.isZero) {
          segments.add(
            CompiledCameraSegment(
              interval: TimelineInterval(
                start: TimelineTime.fromMicroseconds(transitionStart),
                end: TimelineTime.fromMicroseconds(arrival),
                intervalType: 'camera-transition',
                entityId: shot.id.value,
                sourceOperation: 'camera-timeline-compile',
                documentRevision: dependencyKey.documentRevision,
              ),
              kind: transition.type == CameraTransitionType.fade
                  ? CompiledCameraSegmentKind.fade
                  : CompiledCameraSegmentKind.move,
              fromView: previous.view,
              toView: target.view,
              easing: transition.easing,
            ),
          );
        }
        previous = target;
      }
      final end = shotStart + shot.duration.microseconds;
      final lastArrival = shotStart + previous.offset.microseconds;
      if (lastArrival < end) {
        segments.add(
          CompiledCameraSegment(
            interval: TimelineInterval(
              start: TimelineTime.fromMicroseconds(lastArrival),
              end: TimelineTime.fromMicroseconds(end),
              intervalType: 'camera-hold',
              entityId: shot.id.value,
              sourceOperation: 'camera-timeline-compile',
              documentRevision: dependencyKey.documentRevision,
            ),
            kind: CompiledCameraSegmentKind.hold,
            fromView: previous.view,
            toView: previous.view,
            easing: CameraEasing.linear,
          ),
        );
      }
      shots.add(
        CompiledCameraShot(
          id: shot.id,
          interval: TimelineInterval(
            start: TimelineTime.fromMicroseconds(shotStart),
            end: TimelineTime.fromMicroseconds(end),
            intervalType: 'camera-shot',
            entityId: shot.id.value,
            sourceOperation: 'camera-timeline-compile',
            documentRevision: dependencyKey.documentRevision,
          ),
          startView: shot.keyframes.first.view,
          finalView: shot.keyframes.last.view,
          segments: segments,
        ),
      );
      previousSimpleView = shot.keyframes.last.view;
    }
    return CompiledCameraTrack(
      dependencyKey: dependencyKey,
      id: track.id,
      enabled: track.enabled,
      defaultView: track.defaultView,
      contentEnd: shots.isEmpty
          ? TimelineTime.fromMicroseconds(shift)
          : shots.last.interval.end,
      shots: shots,
    );
  }
}
