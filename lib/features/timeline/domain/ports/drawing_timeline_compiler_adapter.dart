import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class AdaptedDrawingTimeline {
  AdaptedDrawingTimeline({
    required this.duration,
    required List<CompiledDrawingSection> sections,
  }) : sections = List.unmodifiable(sections);

  final TimelineDuration duration;
  final List<CompiledDrawingSection> sections;
}

abstract interface class DrawingTimelineCompilerAdapter {
  AdaptedDrawingTimeline compile(ProjectDocument document);
}
