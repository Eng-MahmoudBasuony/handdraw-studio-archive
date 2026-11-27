import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/reference_reveal_motion_policy.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  const policy = ReferenceRevealMotionPolicy();

  test('matches the measured one-second reference content sweep', () {
    final duration = policy.animationDurationSeconds([
      DrawingStroke(
        id: 'reference',
        name: 'Reference span',
        points: const [Offset(0, .5), Offset(241 / 420, .5)],
      ),
    ]);

    expect(duration, closeTo(1, .000001));
  });

  test('keeps identical apparent speed for both horizontal directions', () {
    DrawingStroke stroke(String id, List<Offset> points) => DrawingStroke(
      id: id,
      name: id,
      sectionId: id,
      points: points,
      revealOnly: true,
    );
    final durations = policy.sectionAnimationDurations([
      stroke('left-to-right', const [Offset(.1, .4), Offset(.7, .4)]),
      stroke('right-to-left', const [Offset(.8, .6), Offset(.2, .6)]),
    ]);

    expect(durations['left-to-right'], closeTo(1.04564, .0001));
    expect(
      durations['right-to-left'],
      closeTo(durations['left-to-right']!, .000001),
    );
  });
}
