import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/image_animation_render_policy.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

TimelineSnapshot frame({double? lift, double? distance}) => TimelineSnapshot(
  revealedPaths: const [],
  handPosition: const Offset(30, 40),
  handAngle: 12 * math.pi / 180,
  handVisible: true,
  penLiftProgress: lift,
  penTravelDistance: distance,
);
void main() {
  final project = HandDrawProject(imageAnimationEffect: 'drawPaint');
  test(
    'nearby letter transfers lift proportionally instead of full canvas lift',
    () {
      final near = frame(lift: .5, distance: 2);
      expect(
        ImageAnimationRenderPolicy.penPosition(project, near, 1000).dy,
        closeTo(39.7, .000001),
      );
      final far = frame(lift: .5, distance: 200);
      expect(ImageAnimationRenderPolicy.penPosition(project, far, 1000).dy, 34);
      for (final progress in [0.0, 1.0]) {
        expect(
          (ImageAnimationRenderPolicy.penPosition(
                    project,
                    frame(lift: progress, distance: 2),
                    1000,
                  ) -
                  near.handPosition)
              .distance,
          closeTo(0, .000001),
        );
      }
    },
  );
  test(
    'drawing contact is exact and wrist movement is reduced without lag',
    () {
      final drawing = frame();
      expect(
        ImageAnimationRenderPolicy.penPosition(project, drawing, 1000),
        drawing.handPosition,
      );
      expect(
        ImageAnimationRenderPolicy.handAngle(project, drawing),
        closeTo(2.4 * math.pi / 180, .000001),
      );
      // Independent of previously sampled time (backward seeking or export).
      ImageAnimationRenderPolicy.handAngle(
        project,
        frame(lift: .5, distance: 2),
      );
      expect(
        ImageAnimationRenderPolicy.handAngle(project, drawing),
        closeTo(2.4 * math.pi / 180, .000001),
      );
      final legacy = project.copyWith(imageAnimationEffect: 'legacy');
      expect(
        ImageAnimationRenderPolicy.handAngle(legacy, drawing),
        drawing.handAngle,
      );
      expect(
        ImageAnimationRenderPolicy.penPosition(
          legacy,
          frame(lift: .5, distance: 2),
          1000,
          forceLift: true,
        ).dy,
        22,
      );
    },
  );
  test(
    'adaptive lift scales consistently between preview and export resolutions',
    () {
      final small = ImageAnimationRenderPolicy.penPosition(
        project,
        frame(lift: .5, distance: 2),
        1000,
      );
      final large = ImageAnimationRenderPolicy.penPosition(
        project,
        frame(lift: .5, distance: 4),
        2000,
      );
      expect(40 - large.dy, closeTo((40 - small.dy) * 2, .000001));
    },
  );
}
