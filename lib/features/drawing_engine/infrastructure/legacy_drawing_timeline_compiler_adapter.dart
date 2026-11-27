import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/ports/drawing_timeline_compiler_adapter.dart';

/// Step 4A compatibility adapter over the production drawing scheduler.
///
/// Legacy decimal seconds are converted once at this boundary. Global timeline
/// compilation and resolution remain integer-microsecond based and never
/// depend on HandDrawProject.
final class LegacyDrawingTimelineCompilerAdapter
    implements DrawingTimelineCompilerAdapter {
  const LegacyDrawingTimelineCompilerAdapter();

  @override
  AdaptedDrawingTimeline compile(ProjectDocument document) {
    final project = LegacyProjectViewCache().resolve(
      EditorDocumentState(document: document),
    );
    final duration = _duration(projectTimelineDuration(project));
    return AdaptedDrawingTimeline(
      duration: duration,
      sections: [
        for (final span in projectTimelineSectionSpans(project))
          CompiledDrawingSection(
            sectionId: _sectionId(document, span.sectionId),
            interval: TimelineInterval(
              start: TimelineTime.fromMicroseconds(
                _microseconds(span.startSeconds),
              ),
              end: TimelineTime.fromMicroseconds(
                _microseconds(span.endSeconds),
              ),
              intervalType: 'drawing-section',
              entityId: span.sectionId,
              sourceOperation: 'legacy-drawing-schedule',
            ),
          ),
      ],
    );
  }

  SectionId _sectionId(ProjectDocument document, String value) =>
      document.sections.firstWhere((section) => section.id.value == value).id;

  TimelineDuration _duration(double seconds) =>
      TimelineDuration.fromMicroseconds(_microseconds(seconds));

  int _microseconds(double seconds) =>
      (seconds * Duration.microsecondsPerSecond).round();
}
