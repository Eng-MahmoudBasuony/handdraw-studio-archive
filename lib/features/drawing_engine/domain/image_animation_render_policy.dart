import 'dart:math' as math;
import 'dart:ui';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';

/// Shared by the editor canvas and exported frames, including camera placement.
abstract final class ImageAnimationRenderPolicy {
  static bool authored(HandDrawProject project) =>
      project.imageAnimationEffect != 'legacy';
  static FilterQuality filter(HandDrawProject project) =>
      authored(project) ? FilterQuality.none : FilterQuality.high;
  static Offset penPosition(
    HandDrawProject project,
    TimelineSnapshot frame,
    double height, {
    bool forceLift = false,
  }) =>
      frame.handPosition +
      Offset(
        0,
        (authored(project) || forceLift) && frame.penLiftProgress != null
            ? -math.sin(frame.penLiftProgress! * math.pi) *
                  (authored(project)
                      ? math.min(
                          height * .006,
                          (frame.penTravelDistance ?? 0) * .15,
                        )
                      : height * .018)
            : 0,
      );

  /// Keep the calibrated nib fixed while reducing rapid wrist changes across
  /// tiny letter segments. Stateless, so seeking and export stay identical.
  static double handAngle(HandDrawProject project, TimelineSnapshot frame) =>
      frame.handAngle * (authored(project) ? .2 : 1);

  static bool handVisible(
    HandDrawProject project,
    TimelineSnapshot frame, {
    bool forceLift = false,
  }) =>
      project.showDrawingHand &&
      (frame.handVisible ||
          ((authored(project) || forceLift) && frame.penLiftProgress != null));
}
