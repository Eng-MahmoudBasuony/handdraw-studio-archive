import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class ProjectDocumentFactory {
  const ProjectDocumentFactory();

  ProjectDocument createEmpty({
    required IdGenerator ids,
    String title = 'Untitled Project',
    ProjectCanvas canvas = const ProjectCanvas(width: 1920, height: 1080),
    FrameRate frameRate = FrameRate.fps30,
    TimelineDuration duration = TimelineDuration.zero,
  }) {
    final allocation = IdAllocationContext(generator: ids);
    return ProjectDocument(
      id: allocation.projectId(),
      title: title,
      canvas: canvas,
      frameRate: frameRate,
      duration: duration,
      assets: const [],
      strokes: const [],
      sections: const [],
      sectionOrder: const [],
      scenes: const [],
      audioTracks: const [],
    );
  }
}
