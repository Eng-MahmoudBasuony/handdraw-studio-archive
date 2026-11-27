import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  for (final sectionCount in [40, 200, 1000]) {
    test(
      'drawing adapter preserves production schedule for $sectionCount sections',
      () {
        final document = _scaledDocument(sectionCount);
        final legacy = LegacyProjectViewCache().resolve(
          EditorDocumentState(document: document),
        );
        final expectedDurationUs = (projectTimelineDuration(legacy) * 1000000)
            .round();
        final expectedSpans = projectTimelineSectionSpans(legacy);
        final adapted = const LegacyDrawingTimelineCompilerAdapter().compile(
          document,
        );

        expect(adapted.duration.microseconds, expectedDurationUs);
        expect(adapted.sections, hasLength(expectedSpans.length));
        for (var index = 0; index < expectedSpans.length; index++) {
          expect(
            adapted.sections[index].sectionId.value,
            expectedSpans[index].sectionId,
          );
          expect(
            adapted.sections[index].interval.start.microseconds,
            (expectedSpans[index].startSeconds * 1000000).round(),
          );
          expect(
            adapted.sections[index].interval.end.microseconds,
            (expectedSpans[index].endSeconds * 1000000).round(),
          );
        }
      },
    );
  }
}

ProjectDocument _scaledDocument(int count) {
  final base = projectDocumentParityFixture();
  final sections = [
    for (var index = 0; index < count; index++)
      ProjectSection(
        id: SectionId('section-$index'),
        name: 'Section $index',
        strokeIds: const [],
        timing: DocumentSectionTiming(
          animationDuration: TimelineDuration.fromMicroseconds(20000 + index),
          pauseBefore: TimelineDuration.fromMicroseconds(
            index.isEven ? 1000 : 0,
          ),
          pauseAfter: TimelineDuration.fromMicroseconds(
            index % 3 == 0 ? 2000 : 0,
          ),
        ),
      ),
  ];
  return base.copyWith(
    strokes: const [],
    sections: sections,
    sectionOrder: [for (final section in sections) section.id],
    scenes: const [],
  );
}
