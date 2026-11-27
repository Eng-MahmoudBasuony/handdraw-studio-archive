import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  test('immutable project timing is reused and edits resolve fresh values', () {
    final project = HandDrawProject(
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'line',
          sectionId: 'part',
          points: const [Offset(.1, .5), Offset(.9, .5)],
        ),
      ],
    );
    final resolution = resolveProjectTimeline(project);
    final metrics = projectTimelineSectionMetrics(project);
    final spans = projectTimelineSectionSpans(project);
    expect(identical(resolveProjectTimeline(project), resolution), isTrue);
    expect(identical(projectTimelineSectionMetrics(project), metrics), isTrue);
    expect(identical(projectTimelineSectionSpans(project), spans), isTrue);
    final faster = project.copyWith(drawingSpeed: 2);
    expect(
      resolveProjectTimeline(faster).durationSeconds,
      lessThan(resolution.durationSeconds),
    );
    expect(
      projectTimelineSectionMetrics(faster)['part']!.animationSeconds,
      lessThan(metrics['part']!.animationSeconds),
    );
    expect(
      projectTimelineSectionSpans(faster).last.endSeconds,
      lessThan(spans.last.endSeconds),
    );
    expect(
      resolveProjectTimeline(project, drawingSpeedOverride: 2).durationSeconds,
      resolveProjectTimeline(faster).durationSeconds,
    );
    expect(identical(resolveProjectTimeline(project), resolution), isTrue);
  });
}
